FROM flink:1.17.1
RUN wget -P /opt/flink/lib https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-flink-1.17/0.5.0-incubating/paimon-flink-1.17-0.5.0-incubating.jar
RUN wget -P /opt/flink/lib https://repo1.maven.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/2.8.3-10.0/flink-shaded-hadoop-2-uber-2.8.3-10.0.jar
RUN wget -P /opt/flink/    https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-flink-action/0.5.0-incubating/paimon-flink-action-0.5.0-incubating.jar
