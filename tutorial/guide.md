#### 1. Specify the following configuration options
```shell
SET 'parallelism.default' = '1';
SET 'execution.checkpointing.interval' = '20 s';
SET 'table.exec.sink.upsert-materialize' = 'NONE';
```

#### 2. Create a Paimon Catalog.

Compared to the `InMemory Catalog` the `Paimon Catalog` is persistent and accessible between different Flink SQL Sessions. 
```sql
CREATE CATALOG paimon WITH (
    'type'='paimon',
    'warehouse'='file:/opt/flink/temp/paimon'
);

USE CATALOG paimon;
```

### Part 1: Data Ingestion

#### 3. Create a new `measurements` table, but this time it will be backed by the paimon connector under the **Paimon Catalog**.
```sql
CREATE TABLE measurements (
    sensor_id BIGINT,
    reading DECIMAL(5, 1),
    event_time AS PROCTIME()
) WITH (
    'bucket' = '4',
    'bucket-key'='sensor_id',
    'file.format'='parquet'
);
```

#### Now let's insert some data into the `paimon-measurements` table
```sql
SET 'pipeline.name' = 'Measurements Ingestion';

INSERT INTO measurements
SELECT * FROM `default_catalog`.`default_database`.measurements;
```
<p align="center">
    <img src="../assets/output1.png" width="800" height="400">
</p>


<p align="center">
    <img src="../assets/output2.png" width="500" height="600">
</p>

```shell
SET 'execution.runtime-mode' = 'batch';

SELECT COUNT(*) FROM measurements;

SET 'execution.runtime-mode' = 'streaming';
```

```sql
CREATE TABLE sensor_info (
    sensor_id BIGINT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    generation INT,
    updated_at TIMESTAMP(3),
    PRIMARY KEY (sensor_id) NOT ENFORCED
) WITH (
    'bucket'='1',
    'file.format'='parquet',
    -- Set changelog-producer as 'input'，
    -- this will inform the CDC source not to drop update_before, 
    -- and the downstream pipelines which consume measurements 
    -- as a source will not generate changelog-normalize operator
    'changelog-producer' = 'input' 
);
```

```sql
SET 'pipeline.name' = 'Sensor Info Ingestion';
INSERT INTO sensor_info
SELECT * FROM `default_catalog`.`default_database`.sensor_info;
```

<p align="center">
    <img src="../assets/output3.png" width="450" height="400">
</p>

```shell
SET 'execution.runtime-mode' = 'batch';

Flink SQL> SELECT COUNT(*) AS total_sensor_information FROM sensor_info;
+--------------------------+
| total_sensor_information |
+--------------------------+
|                      100 |
+--------------------------+
1 row in set

SET 'execution.runtime-mode' = 'streaming';
```

### Part 2: Data Enrichment
```sql
CREATE TABLE measurements_enriched (
    sensor_id BIGINT,
    reading DECIMAL(5, 1),
    event_time TIMESTAMP(3),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    generation INT,
    updated_at TIMESTAMP(3)
) WITH (
      'bucket' = '1',
      'bucket-key' = 'sensor_id',
      'file.format' = 'parquet'
);
```

```sql
SET 'pipeline.name' = 'Data Enrichment with Lookup Join';
SET 'table.exec.source.idle-timeout' = '100';
    
INSERT INTO measurements_enriched
SELECT /*+ LOOKUP(
         'table'='s',
         'retry-predicate'='lookup_miss',
         'output-mode'='allow_unordered', 
         'retry-strategy'='fixed_delay', 
         'fixed-delay'='1s',
         'max-attempts'='50'
         ) */
    m.sensor_id,
    m.reading,
    m.event_time,
    s.latitude,
    s.longitude,
    s.generation,
    s.updated_at
FROM measurements AS m
         JOIN sensor_info /*+ OPTIONS('lookup.async'='true', 'lookup.async-thread-number'='16') */
    FOR SYSTEM_TIME AS OF m.event_time AS s
              ON m.sensor_id = s.sensor_id;
```












```sql
CREATE TABLE measurements_agg (
    sensor_id BIGINT,
    max_reading DECIMAL(5, 2),
    min_reading DECIMAL(5, 2),
    total_readings DECIMAL(5, 2),
    last_reading_at TIMESTAMP(3),
        PRIMARY KEY (sensor_id) NOT ENFORCED
) WITH (
    'bucket' = '2',
    'bucket-key' = 'sensor_id',
    'file.format' = 'parquet',
    'merge-engine' = 'aggregation',
    'changelog-producer' = 'lookup',
    'fields.sensor_id.aggregate-function'='last_value',
    'fields.max_reading.aggregate-function'='max',
    'fields.min_reading.aggregate-function'='min',
    'fields.total_readings.aggregate-function'='sum',
    'fields.last_reading_at.aggregate-function'='last_value'
);
```

```sql
INSERT INTO measurements_agg
SELECT 
    sensor_id,
    reading AS max_reading,
    reading AS min_reading,
    reading AS total_readings,
    event_time AS last_reading_at
FROM measurements;
```


```sql
CREATE TABLE readings_enriched (
    sensor_id BIGINT,
    max_reading DECIMAL(5, 2),
    min_reading DECIMAL(5, 2),
    total_readings DECIMAL(5, 2),
    last_reading_at TIMESTAMP(3),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    generation INT,
    updated_at TIMESTAMP(3),
        PRIMARY KEY (sensor_id) NOT ENFORCED
) WITH (
    'bucket' = '2',
    'bucket-key' = 'sensor_id',
    'file.format' = 'parquet',
    'merge-engine'='partial-update',
    'changelog-producer'='lookup'
);
```

```sql
INSERT INTO readings_enriched
SELECT 
    sensor_id,
    max_reading,
    min_reading,
    total_readings,
    last_reading_at,
    CAST (NULL AS DOUBLE) AS latitude,
    CAST (NULL AS DOUBLE) AS longitude,
    CAST (NULL AS INT) AS generation,
    CAST (NULL AS TIMESTAMP(3)) AS updated_at
FROM measurements_agg
UNION ALL
SELECT
    sensor_id,
    CAST (NULL AS DECIMAL(5, 2)) AS max_reading,
    CAST (NULL AS DECIMAL(5, 2)) AS min_reading,
    CAST (NULL AS DECIMAL(5, 2)) AS total_readings,
    CAST (NULL AS TIMESTAMP(3)) AS last_reading_at,
    latitude,
    longitude,
    generation,
    updated_at
FROM sensor_info;
```

```shell
SET 'execution.runtime-mode' = 'batch';

SELECT COUNT(*) FROM readings_enriched;
SELECT * FROM readings_enriched;

SET 'execution.runtime-mode' = 'streaming';
```

#### 10. Run compaction.
```shell
./bin/flink run \
    ./paimon-flink-action-0.5.0-incubating.jar \
    compact \
    --path file:///opt/flink/temp/paimon/default.db/measurements
```

```sql
ALTER TABLE measurements SET (
    'snapshot.time-retained'='5s',
    'snapshot.num-retained.min'='1',
    'snapshot.num-retained.max'='5',
    'full-compaction.delta-commits' = '10',
    'compaction.max.file-num' = '5'
);
```