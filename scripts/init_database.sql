-- create a database called DWH
USE master;
GO

-- Drop and recreate the 'DataWarehouse' database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DWH')
BEGIN
    ALTER DATABASE DWH SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DWH;
END;
GO

-- Create the 'DataWarehouse' database
CREATE DATABASE DWH;
GO

USE DWH;
GO

-- Create Schemas
CREATE SCHEMA bronze;
GO

CREATE SCHEMA silver;
GO

CREATE SCHEMA gold;
GO
