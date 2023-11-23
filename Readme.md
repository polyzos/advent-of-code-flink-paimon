Stream Processing with Apache Flink and Paimon
----------------------------------------------

<p align="center">
    <img src="assets/cover.png" width="600" height="250">
</p>

This repository is a getting started guide for the **[25 Open Source Advent of Code]()**.


### Table of Contents
1. [Environment Setup](#environment-setup)
2. [Flink SQL Client](#flink-sql-client)
3. [Flink SQL Components](#flink-sql-components)
4. [Table Setup](#table-setup)


### Environment Setup
In order to run the tutorial you will need a Flink Cluster and the Apache Paimon dependencies.

We have provided a `docker-compose.yaml` file, that will spin up a Flink Cluster.
We also have a `Dockerfile` that builds on the official Flink image and add the required connector dependencies.

In order to spin-up a Flink cluster, all you have to do is run:
```shell
docker-compose up
```

When the cluster is up navigate to [localhost:8081](localhost:8081) and you should see the Flink Web UI.

**Note:** The docker containers also mount to your local directory, so you should see a directory `logs/flink` created.

All the data files will be created inside that directory.

### Flink SQL Client
In order to execute Flink SQL jobs, we will be using the Flink SQL Client.

Grab a terminal inside your JobManager container
```shell
docker exec -it jobmanager bash
```

then you can start a Flink SQL client, by running:
```shell
./bin/sql-client.sh
```

At this point you are ready to start interacting with Flink.

### Flink SQL Components
The high level component of Flink SQL is the catalog. It keeps metadata about databases, tables, functions and more.

By default the catalog is inMemory, which means everything gets lost when the session closes.

Run the following command:
```shell
Flink SQL> SHOW CATALOGS;
+-----------------+
|    catalog name |
+-----------------+
| default_catalog |
+-----------------+
1 row in set
```
We can see we are under the `default_catalog` and if you run:

```shell
Flink SQL> SHOW DATABASES;
+------------------+
|    database name |
+------------------+
| default_database |
+------------------+
1 row in set
```
We can also see we have a `default_database`.

You can run more commands like `SHOW FUNCTIONS` and `SHOW VIEWS` to view the available functions and views.

### Table Setup
Throughout the tutorial we will needs some table and data to play with.

So let's go and create a few tables and generate some data. 

We will be using some mock data for sensor measurements and sensor information and we will use
Flink's build-in [datagen connector](https://nightlies.apache.org/flink/flink-docs-release-1.18/docs/connectors/table/datagen/) to achieve this.

```sql
CREATE TABLE measurements (
    sensor_id BIGINT,
    reading DECIMAL(5, 1),
    event_time TIMESTAMP(3)
) WITH (
    'connector' = 'datagen',
    'fields.sensor_id.kind'='random',
    'fields.sensor_id.min'='1',
    'fields.sensor_id.max'='100',
    'fields.reading.kind'='random',
    'fields.reading.min'='0.0',
    'fields.reading.max'='45.0',
    'fields.event_time.max-past'='5 s'
);
```

Also run the following command. 
Thi basically changes the output mode of the client when trying to view results.
```shell
SET 'sql-client.execution.result-mode' = 'tableau';
```

Then let's verify we can query our table and see some `measurements` data.
```sql
Flink SQL> SELECT * FROM measurements LIMIT 10;
>
+----+----------------------+---------+-------------------------+
| op |            sensor_id | reading |              event_time |
+----+----------------------+---------+-------------------------+
| +I |                   32 |    24.2 | 2023-11-23 07:30:55.848 |
| +I |                   16 |    25.6 | 2023-11-23 07:30:52.166 |
| +I |                   53 |     4.5 | 2023-11-23 07:30:54.164 |
| +I |                   70 |     6.3 | 2023-11-23 07:30:53.361 |
| +I |                   51 |    29.0 | 2023-11-23 07:30:53.924 |
| +I |                   31 |     0.3 | 2023-11-23 07:30:55.476 |
| +I |                    8 |     7.4 | 2023-11-23 07:30:52.400 |
| +I |                   60 |    12.2 | 2023-11-23 07:30:51.277 |
| +I |                   68 |    19.6 | 2023-11-23 07:30:55.154 |
| +I |                   87 |    34.3 | 2023-11-23 07:30:52.322 |
+----+----------------------+---------+-------------------------+
Received a total of 10 rows
```

We will create another table called `sensor_info`.
```sql
CREATE TABLE sensor_info (
    sensor_id BIGINT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    generation INT,
    updated_at TIMESTAMP(3)
) WITH (
    'connector' = 'datagen',
    'number-of-rows'='10000',
    'fields.sensor_id.kind'='random',
    'fields.sensor_id.min'='1',
    'fields.sensor_id.max'='100',
    'fields.latitude.kind'='random',
    'fields.latitude.min'='-90.0',
    'fields.latitude.max'='90.0',
    'fields.longitude.kind'='random',
    'fields.longitude.min'='-180.0',
    'fields.longitude.max'='180.0',
    'fields.generation.kind'='random',
    'fields.generation.min'='0',
    'fields.generation.max'='3',
    'fields.updated_at.max-past'='0'
);
```
Notice how we specify we want `10000` records, so this means that this table is `bounded`, i.e its not a never-ending stream with events.

```sql
Flink SQL> SELECT * FROM sensor_info LIMIT 10;
>
+----+----------------------+--------------------------------+--------------------------------+-------------+-------------------------+
| op |            sensor_id |                       latitude |                      longitude |  generation |              updated_at |
+----+----------------------+--------------------------------+--------------------------------+-------------+-------------------------+
| +I |                   80 |              81.86511315876018 |              54.55085194269276 |           2 | 2023-11-23 07:33:46.959 |
| +I |                    5 |              85.25579038990347 |              -141.729484364909 |           2 | 2023-11-23 07:33:46.960 |
| +I |                   81 |              59.28885905269882 |             125.25733278264516 |           1 | 2023-11-23 07:33:46.960 |
| +I |                   31 |             -68.93407946310646 |            -148.84245945377683 |           2 | 2023-11-23 07:33:46.960 |
| +I |                    1 |            -26.012451262689765 |              15.43214445471898 |           1 | 2023-11-23 07:33:46.960 |
| +I |                   64 |               52.5999653172305 |              46.85505502069498 |           0 | 2023-11-23 07:33:46.960 |
| +I |                   34 |             -29.75182311185338 |            -28.679515250258333 |           1 | 2023-11-23 07:33:46.960 |
| +I |                   35 |              70.47215865601012 |             -99.79991569639377 |           0 | 2023-11-23 07:33:46.960 |
| +I |                   25 |             20.618020925638717 |            -0.5002813485619697 |           3 | 2023-11-23 07:33:46.960 |
| +I |                   71 |              47.85809156450427 |             110.42800034166112 |           0 | 2023-11-23 07:33:46.960 |
+----+----------------------+--------------------------------+--------------------------------+-------------+-------------------------+
Received a total of 10 rows
```

With our tables containing some data, we are ready now to go and start with **Apache Paimon**.

You can find the tutorial guide under the `tutorial/guide.md` file.