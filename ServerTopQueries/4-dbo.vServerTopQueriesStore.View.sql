----------------------------------------------------------------------------------
-- View Name: [dbo].[vServerTopQueriesStore]
--
-- Desc: This view is built on top of [ServerTopQueriesStore] to extract the details of the top queries identified by the execution of [dbo].[ServerTopQueries]
--
--		[ReportID]				BIGINT			NOT NULL
--			Unique Identifier for the execution (operations not logged to table have no ReportID)
--
--		[DatabaseName]			SYSNAME			NOT NULL
--			Name of the databse the information of the following columns has been extracted from
--
--		[QueryID]				BIGINT			NOT NULL
--			Identifier of the query the statistics are associated to
--
--		[MinNumberPlans]		INT				NOT NULL
--			Minimum number of execution plans found for the QueryID
--
--		[QueryTextID]			BIGINT			NOT NULL
--			Identifier of the Query Text belonging to the corresponding [QueryID]
--
--		[ObjectID]				BIGINT			NOT NULL
--			Identifier of the object associated to the corresponding [QueryID] (if any)
--
--		[SchemaName]			SYSNAME			    NULL
--			Name of the schema of the object associated to the corresponding [QueryID] (if any)
--
--		[ObjectName]			SYSNAME			    NULL
--			Name of the object associated to the corresponding [QueryID] (if any)
--
--		[ExecutionTypeDesc]		NVARCHAR(120)	NOT NULL
--			Description of the execution type (Regular, Aborted, Exception)
--
--		[ExecutionCount]		BIGINT			NOT NULL
--			Number of executions of the corresponding [PlanID] and with the same [ExecutionTypeDes]
--
--		[Duration]				BIGINT			NOT NULL
--			Total duration of all executions of the corresponding [PlanID] in microseconds
--
--		[CPU]					BIGINT			NOT NULL
--			Total CPU time of all executions of the corresponding [PlanID] in microseconds
--
--		[LogicalIOReads]		BIGINT			NOT NULL
--			Total Logical IO reads of all executions of the corresponding [PlanID] in 8 KB pages
--
--		[LogicalIOWrites]		BIGINT			NOT NULL
--			Total Logical IO Writes of all executions of the corresponding [PlanID] in 8 KB pages
--
--		[PhysicalIOReads]		BIGINT			NOT NULL
--			Total Physical IO Reads of all executions of the corresponding [PlanID] in 8 KB pages
--
--		[CLR]					BIGINT			NOT NULL
--			Total CLR time of all executions of the corresponding [PlanID] in microseconds
--
--		[Memory]				BIGINT			NOT NULL
--			Total Memory usage of all executions of the corresponding [PlanID] in 8 KB pages
--
--		[LogBytes]				BIGINT				NULL
--			Total Log bytes usage of all executions of the corresponding [PlanID] in Bytes
--			NULL for SQL 2016 (the metric is not registered in this version)
--
--		[TempDBSpace]			BIGINT				NULL
--			Total TempDB space usage of all executions of the corresponding [PlanID] in 8 KB pages
--			NULL for SQL 2016 (the metric is not registered in this version)
--
--		[QuerySqlText]			NVARCHAR(MAX)	    NULL
--			Query Text corresponding to the [PlanID]
--
-- Date: 2020.10.22
-- Auth: Pablo Lozano (@sqlozano)
--
-- Date: 2021.08.19
-- Auth: Pablo Lozano (@sqlozano)
-- Changes: Modified view to replace [PlanID] with [MinNumberPlans]
----------------------------------------------------------------------------------

CREATE OR ALTER VIEW [dbo].[vServerTopQueriesStore]
AS
SELECT
	 [stqi].[ReportID]
	,[stqi].[CaptureDate]
	,[stqi].[ServerIdentifier]
	,[stqi].[Measurement]
	,[stqs].[DatabaseName]
	,[stqs].[QueryID]
	,[stqs].[MinNumberPlans]
	,[stqs].[QueryTextID]
	,[stqs].[ObjectID]
	,[stqs].[SchemaName]
	,[stqs].[ObjectName]
	,[stqs].[ExecutionTypeDesc]
	,[stqs].[ExecutionCount]
	,[stqs].[Duration]
	,[stqs].[CPU]
	,[stqs].[LogicalIOReads]
	,[stqs].[LogicalIOWrites]
	,[stqs].[PhysicalIOReads]
	,[stqs].[CLR]
	,[stqs].[Memory]
	,[stqs].[LogBytes]
	,[stqs].[TempDBSpace]
	,CAST(DECOMPRESS([stqs].[QuerySqlText]) AS NVARCHAR(MAX))	AS [QuerySqlText]
FROM [dbo].[vServerTopQueriesIndex] [stqi]
INNER JOIN [dbo].[ServerTopQueriesStore] [stqs]
ON [stqi].[ReportID] = [stqs].[ReportID]