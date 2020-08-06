SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

----------------------------------------------------------------------------------
-- Procedure Name: GetServerTopQueries
--
-- Desc: This script loops all the accessible user DBs (or just the selected one) and gathers the TOP XX queries based on the selected measurement and generates a report
--
--
-- Parameters:
--	INPUT
--		@ServerIdentifier			SYSNAME			--	Identifier assigned to the server.
--														[Default: @@SERVERNAME]
--
--		@DatabaseName				SYSNAME			--	Name of the database to generate this report on.
--														[Default: NULL, all databases on the server are processed]
--
--		@ReportIndex				NVARCHAR(800)	--	Table to store the details of the report, such as parameters used, if no results returned to the user are required
--														[Default: NULL, results returned to user]
--
--		@ReportTable				NVARCHAR(800)	--	Table to store the results of the report, if no results returned to the user are required. 
--														[Default: NULL, results returned to user]
--
--		@StartTime					DATETIME		--	Start time of the period to analyze, in UTC format.
--														[Default: DATEADD(HOUR,-1,GETUTCDATE()]
--
--		@EndTime					DATETIME2		--	End time of the period to analyze, in UTC format.
--														[Default: GETUTCDATE()]
--
--		@Top						INT				--	Number of queries to extract from each database.
--														[Default: 25]
--
--		@Measurement				NVARCHAR(32)	--	Measurement to order the results by, to select from:
--															duration
--															cpu_time
--															logical_io_reads
--															logical_io_writes
--															physical_io_reads
--															clr_time
--															query_used_memory
--															log_bytes_used
--															tempdb_space_used
--														[Default: cpu_time]
--
--		@IncludeQueryText			BIT				--	Flag to include the query text in the results.
--														[Default: 0]
--
--		@VerboseMode				BIT				--	Flag to determine whether the T-SQL commands that compose this report will be returned to the user.
--														[Default: 0]
--
--		@TestMode					BIT				--	Flag to determine whether the actual T-SQL commands that generate the report will be executed.
--														[Default: 0]
--
--	OUTPUT
--		@ReportID					BIGINT			--	Returns the ReportID (when the report is being logged into a table)
--
-- Date: 2019-08-28
-- Auth: Pablo Lozano
----------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE [dbo].[GetServerTopQueries]
(
	@ServerIdentifier		SYSNAME			= NULL,	
	@DatabaseName			SYSNAME			= NULL,
	@ReportIndex			NVARCHAR(800)	= NULL,
	@ReportTable			NVARCHAR(800)	= NULL,
	@StartTime				DATETIME2		= NULL,
	@EndTime				DATETIME2		= NULL,
	@Top					INT				= 25,
	@Measurement			NVARCHAR(32)	= 'cpu_time',
	@IncludeQueryText		BIT				= 0,
	@VerboseMode			BIT				= 0,
	@TestMode				BIT				= 0,
	@ReportID				BIGINT			=	NULL	OUTPUT
)
AS
BEGIN
SET NOCOUNT ON
-- Check variables and set defaults - START
IF (@ServerIdentifier IS NULL)
	SET @ServerIdentifier = @@SERVERNAME

IF (@StartTime IS NULL) OR (@EndTime IS NULL)
BEGIN
	SET @StartTime	= DATEADD(HOUR,-1, GETUTCDATE())
	SET	@EndTime	= GETUTCDATE()
END
	
IF (@Top < 0) OR (@Top IS NULL)
	SET @Top = 0

IF	(@Measurement NOT IN 
		(
		'duration',
		'cpu_time',
		'logical_io_reads',
		'logical_io_writes',
		'physical_io_reads',
		'clr_time',
		'query_used_memory',
		'log_bytes_used',
		'tempdb_space_used'
		)
	)
BEGIN
	RAISERROR('The measurement [%s] is not valid. Valid values are:
		[duration]
		[cpu_time]
		[logical_io_reads]
		[logical_io_writes]
		[physical_io_reads]
		[clr_time]
		[query_used_memory]
		[log_bytes_used]
		[tempdb_space_used]', 16, 0, @DatabaseName)
	RETURN
END

IF (@IncludeQueryText IS NULL)
	SET @IncludequeryText = 0
-- Check variables and set defaults - END


-- Define databases in scope for the report - START
DECLARE @dbs TABLE
(
    DatabaseName sysname
)
	--Specific @DatabaseName provided - START
	IF (@DatabaseName IS NOT NULL) AND (@DatabaseName <> '')
	BEGIN
		-- Check whether @DatabaseName actually exists - START
		IF NOT EXISTS (SELECT 1 FROM [sys].[databases] WHERE [name] = @DatabaseName)
		BEGIN
			RAISERROR('The database [%s] does not exist', 16, 0, @DatabaseName)
			RETURN
		END
		-- Check whether @DatabaseName actually exists - END
		
		-- Check whether @DatabaseName is ONLINE - START
		IF EXISTS (SELECT 1 FROM [sys].[databases] WHERE [name] = @DatabaseName AND [state_desc] <> 'ONLINE')
		BEGIN
			RAISERROR('The database [%s] is not online', 16, 0, @DatabaseName)
			RETURN
		END
		-- Check whether @DatabaseName is ONLINE - END
		INSERT INTO @dbs ([DatabaseName]) VALUES (@DatabaseName)
	END
	--Specific @DatabaseName provided - END

	-- No @DatabaseName provided: all databases in scope - START
	IF (@DatabaseName IS NULL) OR (@DatabaseName = '')
	BEGIN
		INSERT INTO @dbs ([DatabaseName])
		SELECT [name] FROM [sys].[databases] WHERE [state_desc] = 'ONLINE'
	END
	-- No @DatabaseName provided: all databases in scope - END
-- Define databases in scope for the report - END

-- Definition of temp table to store the reports for each database - START
DROP TABLE IF EXISTS #ServerTopQueriesStore
CREATE TABLE #ServerTopQueriesStore
(
	[DatabaseName]			SYSNAME			NOT NULL,
	[PlanID]				BIGINT			NOT NULL,
	[QueryID]				BIGINT			NOT NULL,
	[QueryTextID]			BIGINT			NOT NULL,
	[ObjectID]				BIGINT			NOT NULL,
	[SchemaName]			SYSNAME			    NULL,
	[ObjectName]			SYSNAME			    NULL,
	[ExecutionTypeDesc]		NVARCHAR(120)	NOT NULL,
	[ExecutionCount]		BIGINT			NOT NULL,
	[duration]				BIGINT			NOT NULL,
	[cpu_time]				BIGINT			NOT NULL,
	[logical_io_reads]		BIGINT			NOT NULL,
	[logical_io_writes]		BIGINT			NOT NULL,
	[physical_io_reads]		BIGINT			NOT NULL,
	[clr_time]				BIGINT			NOT NULL,
	[query_used_memory]		BIGINT			NOT NULL,
	[log_bytes_used]		BIGINT			NOT NULL,
	[tempdb_space_used]		BIGINT			NOT NULL,
	[QuerySqlText]			VARBINARY(MAX)	    NULL
)
-- Definition of temp table to store the reports for each database - END

-- Query to extract the details for any given @DatabaseName - START
DECLARE @SqlCommand2PopulateTempTableTemplate NVARCHAR(MAX)
SET @SqlCommand2PopulateTempTableTemplate = 'USE {@DatabaseName}
;WITH dbdata AS
(
SELECT
       [qsrs].[plan_id],
       [qsp].[query_id],
       [qsq].[query_text_id],
	   ISNULL([obs].[object_id], 0) as [object_id],
       ISNULL(SCHEMA_NAME([obs].[schema_id]), '''') AS [SchemaName],
       ISNULL(OBJECT_NAME([obs].[object_id]), '''') AS [ProcedureName],
       [qsrs].[execution_type_desc],
       SUM([qsrs].[count_executions]) AS [count_executions],
       CAST(SUM([qsrs].[avg_duration]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [duration],
       CAST(SUM([qsrs].[avg_cpu_time]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [cpu_time],
       CAST(SUM([qsrs].[avg_logical_io_reads])  * SUM([qsrs].[count_executions]) AS BIGINT) AS [logical_io_reads],
       CAST(SUM([qsrs].[avg_logical_io_writes]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [logical_io_writes],
       CAST(SUM([qsrs].[avg_physical_io_reads]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [physical_io_reads],
       CAST(SUM([qsrs].[avg_clr_time]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [clr_time],
       CAST(SUM([qsrs].[avg_query_max_used_memory]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [query_used_memory],
       CAST(SUM([qsrs].[avg_log_bytes_used]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [log_bytes_used],
       CAST(SUM([qsrs].[avg_tempdb_space_used]) * SUM([qsrs].[count_executions]) AS BIGINT) AS [tempdb_space_used]
FROM
{@DatabaseName}.[sys].[query_store_runtime_stats] [qsrs]
INNER JOIN {@DatabaseName}.[sys].[query_store_runtime_stats_interval] [qsrsi]
ON [qsrs].[runtime_stats_interval_id] = [qsrsi].[runtime_stats_interval_id]
INNER JOIN {@DatabaseName}.[sys].[query_store_plan] [qsp]
ON [qsrs].[plan_id] = [qsp].[plan_id]
INNER JOIN {@DatabaseName}.[sys].[query_store_query] [qsq]
ON [qsp].[query_id] = [qsq].[query_id]
LEFT JOIN {@DatabaseName}.[sys].[objects] [obs]
ON [qsq].[object_id] = [obs].[object_id]
WHERE [qsrsi].[end_time] >= ''{@StartTime}'' AND [qsrsi].[start_time] <= ''{@EndTime}''
GROUP BY [qsrs].[plan_id], [qsp].[query_id], [qsq].[query_text_id], [obs].[schema_id], [obs].[object_id], [qsrs].[execution_type_desc]
)
 
INSERT INTO #ServerTopQueriesStore
SELECT
    {@Top}
    ''{@DatabaseName_NoQuotes}''
	,[dbdata].*
	,{@IncludeQueryText_Value} AS [query_sql_text] 
FROM [dbdata]
{@IncludeQueryText_Join}
{@Order}'

	SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@StartTime}',				CAST(@StartTime AS NVARCHAR(34)))
	SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@EndTime}',				CAST(@EndTime AS NVARCHAR(34)))

	-- Based on @IncludeQueryText, include the query text in the reports or not - START
	IF (@IncludeQueryText = 0)
	BEGIN
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@IncludeQueryText_Value}',	'NULL')
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@IncludeQueryText_Join}',	'')
	END
	IF (@IncludeQueryText = 1)
	BEGIN
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@IncludeQueryText_Join}',	'INNER JOIN {@DatabaseName}.[sys].[query_store_query_text] [qsqt] ON [dbdata].[query_text_id] = [qsqt].[query_text_id]')
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@IncludeQueryText_Value}',	'COMPRESS([qsqt].[query_sql_text])')
	END
	-- Based on @IncludeQueryText, include the query text in the reports or not - END

	-- Based on @Top, return only the @Top queries or all - START
	IF (@Top > 0)
	BEGIN
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@Top}',				'TOP('+CAST(@Top AS NVARCHAR(8))+')')
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@Order}',				'ORDER BY {@Measurement} DESC')
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@Measurement}',		QUOTENAME(@Measurement))
	END
	IF (@Top = 0)
	BEGIN
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@Top}',				'')
		SET @SqlCommand2PopulateTempTableTemplate = REPLACE(@SqlCommand2PopulateTempTableTemplate, '{@Order}',				'')
	END
	-- Based on @Top, return only the @Top queries or all - END

-- Query to extract the details for any given @DatabaseName - END 
 
 
-- Loop through all the databases in scope to load their details into #ServerTopQueriesStore - START
DECLARE @CurrentDBTable TABLE(
    DatabaseName  SYSNAME
)
DECLARE @CurrentDB SYSNAME

DECLARE @SqlCommand2PopulateTempTable NVARCHAR(MAX)
WHILE EXISTS (SELECT 1 FROM @dbs)
BEGIN
    DELETE TOP(1) FROM @dbs
    OUTPUT deleted.DatabaseName INTO @CurrentDBTable
    SELECT @CurrentDB = DatabaseName FROM @CurrentDBTable
    SET @SqlCommand2PopulateTempTable	=	REPLACE(@SqlCommand2PopulateTempTableTemplate,	'{@DatabaseName}',			QUOTENAME(@CurrentDB))
	SET @SqlCommand2PopulateTempTable	=	REPLACE(@SqlCommand2PopulateTempTable,			'{@DatabaseName_NoQuotes}',	@CurrentDB)
    IF (@VerboseMode = 1)	PRINT	(@SqlCommand2PopulateTempTable)
	IF (@TestMode = 0)		EXECUTE	(@SqlCommand2PopulateTempTable)
END
-- Loop through all the databases in scope to load their details into #ServerTopQueriesStore - END


-- Output to user - START
IF (@ReportTable IS NULL) OR (@ReportTable = '') OR (@ReportIndex IS NULL) OR (@ReportIndex = '')
BEGIN
	DECLARE @SqlCmd2User NVARCHAR(MAX) = 'SELECT * FROM #ServerTopQueriesStore ORDER BY {@Measurement} DESC'
	SET @SqlCmd2User = REPLACE(@SqlCmd2User,	'{@Measurement}', QUOTENAME(@Measurement))
	IF (@VerboseMode = 1)	PRINT (@SqlCmd2User)
	IF (@TestMode = 0)		EXEC (@SqlCmd2User)
END
-- Output to user - END

-- Output to table - START
IF (@ReportTable IS NOT NULL) AND (@ReportTable <> '') AND (@ReportIndex IS NOT NULL) AND (@ReportIndex <> '')
BEGIN
	-- Log report entry in [dbo].[ServerLoadIndex] - START
	DECLARE @SqlCmdIndex NVARCHAR(MAX) =
	'INSERT INTO {@ReportIndex}
	(
		[CaptureDate],
		[ServerIdentifier],
		[DatabaseName],
		[Top],
		[Measurement],
		[StartTime],
		[EndTime]
	)
	VALUES
	(
		SYSUTCDATETIME(),
		''{@ServerIdentifier}'',
		''{@DatabaseName}'',
		{@Top},
		''{@Measurement}'',
		''{@StartTime}'',
		''{@EndTime}''
	)'

	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ReportIndex}',		@ReportIndex)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@ServerIdentifier}',	@ServerIdentifier)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@DatabaseName}',		ISNULL(@DatabaseName,'*'))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@Top}',				@Top)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@Measurement}',		@Measurement)
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@StartTime}',		CAST(@StartTime AS NVARCHAR(34)))
	SET @SqlCmdIndex = REPLACE(@SqlCmdIndex, '{@EndTime}',			CAST(@EndTime AS NVARCHAR(34)))

	IF (@VerboseMode = 1)	PRINT (@SqlCmdIndex)
	IF (@TestMode = 0)		EXEC (@SqlCmdIndex)

	SET @ReportID = IDENT_CURRENT(@ReportIndex)
	-- Log report entry in [dbo].[ServerLoadIndex] - END


	DECLARE @SqlCmd2Table NVARCHAR(MAX) = 'INSERT INTO {@ReportTable}
	SELECT
		{@ReportID},
		[DatabaseName],
		[PlanID],
		[QueryID],
		[QueryTextID],
		[ObjectID],
		[SchemaName],
		[ObjectName],
		[ExecutionTypeDesc],
		[ExecutionCount],
		[duration],
		[cpu_time],
		[logical_io_reads],
		[logical_io_writes],
		[physical_io_reads],
		[clr_time],
		[query_used_memory],
		[log_bytes_used],
		[tempdb_space_used],
		[QuerySqlText]	
	FROM #ServerTopQueriesStore'

	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ReportTable}',		@ReportTable) 
	SET @SqlCmd2Table = REPLACE(@SqlCmd2Table, '{@ReportID}',			@ReportID) 

	IF (@VerboseMode = 1)	PRINT (@SqlCmd2Table)
	IF (@TestMode = 0)		EXEC (@SqlCmd2Table)
END
-- Output to table - END

DROP TABLE IF EXISTS #ServerTopQueriesStore

RETURN
END
GO