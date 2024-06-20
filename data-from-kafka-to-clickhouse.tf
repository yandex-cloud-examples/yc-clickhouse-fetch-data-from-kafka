# Infrastructure for the Yandex Cloud Managed Service for Apache Kafka® and Managed Service for ClickHouse® clusters
#
# RU: https://yandex.cloud/ru/docs/managed-clickhouse/tutorials/fetch-data-from-mkf
# EN: https://yandex.cloud/en/docs/managed-clickhouse/tutorials/fetch-data-from-mkf
#
# Configure the parameters of the Managed Service for Apache Kafka® and Managed Service for ClickHouse® clusters:

locals {
  # Settings for Managed Service for Apache Kafka® cluster:
  kafka-version     = "" # Desired version of Apache Kafka®. For available versions, see the documentation main page: https://yandex.cloud/en/docs/managed-kafka/.
  producer_name     = "" # Username with the producer role
  producer_password = "" # Password of the user with the producer role
  topic_name        = "" # Apache Kafka® topic name. Each Managed Service for Apache Kafka® cluster must have its unique topic name.
  consumer_name     = "" # Username with the consumer role
  consumer_password = "" # Password of the user with the consumer role

  # Settings for Managed Service for ClickHouse® cluster:
  db_user_name     = "" # Username of the ClickHouse® cluster
  db_user_password = "" # ClickHouse® user's password

  # The following settings are predefined. Change them only if necessary.
  network_name            = "network"            # Name of the network
  subnet_name             = "subnet-a"           # Name of the subnet
  zone_a_v4_cidr_blocks   = "10.1.0.0/16"        # CIDR block for subnet in the ru-central1-a availability zone
  kafka_cluster_name      = "kafka-cluster"      # Name of the Apache Kafka® cluster. If you are going to create multiple clusters, then duplicate, rename, and edit this variable.
  clickhouse_cluster_name = "clickhouse-cluster" # Name of the ClickHouse® cluster
  clickhouse_db_name      = "db1"                # Name of the ClickHouse® cluster database
}

# Network infrastructure

resource "yandex_vpc_network" "network" {
  description = "Network for the Managed Service for Apache Kafka® and Managed Service for ClickHouse® clusters"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_default_security_group" "security-group" {
  description = "Security group for the Managed Service for Apache Kafka® and Managed Service for ClickHouse® clusters"
  network_id  = yandex_vpc_network.network.id

  ingress {
    description    = "Allows connections to the Managed Service for Apache Kafka® cluster from the Internet"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allows connections to the Managed Service for ClickHouse® cluster from the Internet"
    protocol       = "TCP"
    port           = 9440
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allows outgoing connections to any required resource"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Infrastructure for the Managed Service for Apache Kafka® cluster

resource "yandex_mdb_kafka_cluster" "kafka-cluster" {
  description        = "Managed Service for Apache Kafka® cluster"
  name               = local.kafka_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_default_security_group.security-group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = local.kafka-version
    zones            = ["ru-central1-a"]
    kafka {
      resources {
        resource_preset_id = "s2.micro"
        disk_type_id       = "network-hdd"
        disk_size          = 10 # GB
      }
    }
  }

  depends_on = [
    yandex_vpc_subnet.subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_topic" "events" {
  cluster_id         = yandex_mdb_kafka_cluster.kafka-cluster.id
  name               = local.topic_name
  partitions         = 4
  replication_factor = 1
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "user-producer" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.producer_name
  password   = local.producer_password
  permission {
    topic_name = yandex_mdb_kafka_topic.events.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# User of the Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_user" "user-consumer" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.consumer_name
  password   = local.consumer_password
  permission {
    topic_name = yandex_mdb_kafka_topic.events.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
}

# Infrastructure for the Managed Service for ClickHouse® cluster

resource "yandex_mdb_clickhouse_cluster" "clickhouse-cluster" {
  description        = "Managed Service for ClickHouse® cluster"
  name               = local.clickhouse_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_default_security_group.security-group.id]

  clickhouse {
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 10 # GB
    }

    # Uncomment the next block if you are going to use only one Managed Service for Apache Kafka® cluster

    #config {
    #  kafka {
    #    security_protocol = "SECURITY_PROTOCOL_SASL_SSL"
    #    sasl_mechanism    = "SASL_MECHANISM_SCRAM_SHA_512"
    #    sasl_username     = yandex_mdb_kafka_user.user-consumer.name
    #    sasl_password     = yandex_mdb_kafka_user.user-consumer.password
    #  }
    #}

    # Uncomment the next block if you are going to use multiple Managed Service for Apache Kafka® clusters. Specify topic name and consumer credentials.

    #config {
    #  kafka_topic {
    #    name = "<topic name>"
    #    settings {
    #    security_protocol = "SECURITY_PROTOCOL_SASL_SSL"
    #    sasl_mechanism    = "SASL_MECHANISM_SCRAM_SHA_512"
    #    sasl_username     = "<name of the user for the consumer>"
    #    sasl_password     = "<password of the user for the consumer>"
    #    }
    #  }
    #}

  }

  host {
    type             = "CLICKHOUSE"
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.subnet-a.id
    assign_public_ip = true # Required for connection from the Internet
  }

  database {
    name = local.clickhouse_db_name
  }

  user {
    name     = local.db_user_name
    password = local.db_user_password
    permission {
      database_name = local.clickhouse_db_name
    }
  }
}
