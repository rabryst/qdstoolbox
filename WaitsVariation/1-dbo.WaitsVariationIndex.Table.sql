----------------------------------------------------------------------------------
-- Table Name: [dbo].[WaitsVariationIndex]
--
-- Desc: This table is used by the procedure [dbo].[WaitsVariation] to store its entry parameters
--
-- Columns:
--		[ReportID]				BIGINT			NOT NULL
--			Unique Identifier for the execution (operations not logged to table have no ReportID)
--
--		[ReportDate]			DATETIME2		NOT NULL
--			UTC Date of the execution's start
--
--		[InstanceIdentifier]		SYSNAME			NOT NULL
--			Identifier of the instance, so if this data is centralized reports originated on each instance can be properly identified
--
--		[DatabaseName]			SYSNAME			NOT NULL
--			Name of the database this operation was executed against
--
--		[Parameters]			XML					NULL
--			List of parameters used to invoke the execution of [dbo].[WaitsVariation]
--
-- Date: 2020.10.22
-- Auth: Pablo Lozano (@sqlozano)
--
-- Date: 2021.04.04
-- Auth: Pablo Lozano (@sqlozano)
--			Replaced "server" references to the more accurate term "instance"
--			Script now drops & recreates the table
----------------------------------------------------------------------------------

DROP TABLE IF EXISTS [dbo].[WaitsVariationIndex]
CREATE TABLE [dbo].[WaitsVariationIndex]
(
	 [ReportID]				BIGINT	IDENTITY(1,1)
	,[CaptureDate]			DATETIME2		NOT NULL
	,[InstanceIdentifier]	SYSNAME			NOT NULL
	,[DatabaseName]			SYSNAME			NOT NULL
	,[Parameters]			XML				NOT NULL
)
ALTER TABLE [dbo].[WaitsVariationIndex]
ADD CONSTRAINT [PK_WaitsVariationIndex] PRIMARY KEY CLUSTERED
(
	 [ReportID]	
)