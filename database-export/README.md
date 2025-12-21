# MongoDB Database Export Tool

A standalone tool to export MongoDB databases to JSON format compatible with the MongoDB Admin UI import feature.

## When to Use This Tool

Use this tool when you need to:
- Export databases from an **old/existing MongoDB server**
- Migrate data to the new MongoDB Admin UI
- Create backups in Admin UI import format

**You don't need this tool** if you're only using the Admin UI to manage the current MongoDB instance.

## Installation

Install dependencies (only needed if you want to use the export tool):

```bash
cd database-export
npm install
```

This will install the `mongodb` driver (required for connecting to MongoDB servers).

## Usage

### Basic Export (No TLS)

```bash
node export-database.js "mongodb://username:password@host:27017/database_name"
```

### Export with TLS

```bash
node export-database.js "mongodb://username:password@host:27017/database_name?tls=true&tlsCAFile=../tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

### Specify Output File

```bash
node export-database.js "mongodb://username:password@host:27017/database_name" output.json
```

### Using npm script

```bash
npm run export "mongodb://username:password@host:27017/database_name"
```

## Connection String Examples

### Local MongoDB (No Auth)
```bash
node export-database.js "mongodb://localhost:27017/mydb"
```

### With Authentication
```bash
node export-database.js "mongodb://user:pass@localhost:27017/mydb?authSource=admin"
```

### Remote Server with TLS
```bash
node export-database.js "mongodb://user:pass@remote-server:27017/mydb?tls=true&tlsCAFile=../tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

### MongoDB Atlas
```bash
node export-database.js "mongodb+srv://user:pass@cluster.mongodb.net/dbname?retryWrites=true&w=majority"
```

## Output Format

The tool creates a JSON file in the following format:

```json
{
  "database": "database_name",
  "exportedAt": "2025-12-21T00:00:00.000Z",
  "collections": {
    "collection1": [
      { "_id": "...", "field1": "value1" },
      { "_id": "...", "field2": "value2" }
    ],
    "collection2": [
      { "_id": "...", "field3": "value3" }
    ]
  }
}
```

This format is directly compatible with the MongoDB Admin UI import feature.

## Importing to Admin UI

After exporting:

1. Access the Admin UI at `http://localhost:3000`
2. Create the database (if it doesn't exist) using the "+ New" button
3. Click "Import" on the database
4. Select the exported JSON file
5. Choose whether to drop existing collections
6. Click "Import"

## Features

- ✅ Exports all collections from a database
- ✅ Preserves document structure and IDs
- ✅ Handles TLS connections
- ✅ Supports authentication
- ✅ Shows progress and statistics
- ✅ Creates Admin UI compatible JSON format

## Troubleshooting

### Connection Errors

**"Authentication failed"**
- Check username and password
- Ensure `authSource` is correct (usually `admin`)
- Verify user has access to the database

**"TLS handshake failed"**
- Ensure TLS is enabled in connection string: `?tls=true`
- Check CA certificate path is correct
- Use `tlsAllowInvalidCertificates=true` for self-signed certs

**"Database name not found"**
- Ensure connection string format: `mongodb://user:pass@host:port/dbname`
- Database name must come after the port

### Large Databases

For very large databases (>500MB):
- Consider exporting collections individually
- The Admin UI has a 500MB import limit
- Use `mongodump` for large databases, then convert selectively

## Examples

### Export from Local MongoDB
```bash
node export-database.js "mongodb://localhost:27017/mydb"
```

### Export from Remote Server
```bash
node export-database.js "mongodb://admin:password@192.168.1.100:27017/production_db?authSource=admin"
```

### Export with Custom Output
```bash
node export-database.js "mongodb://user:pass@host:27017/dbname" my_backup.json
```

## Requirements

- Node.js 14+ 
- MongoDB driver (installed via `npm install`)
- Access to source MongoDB server
