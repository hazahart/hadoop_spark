#!/bin/bash

echo "Instalando dependencias necesarias (incluyendo wget y curl)..."
sudo apt update
sudo apt install -y python3 python3-pip python3-venv wget curl

echo "Buscando la última versión de Apache Spark automáticamente..."
# Extraemos la última versión leyendo la página oficial de descargas
SPARK_VERSION=$(curl -s https://spark.apache.org/downloads.html | grep -E -o "spark-[0-9]+\.[0-9]+\.[0-9]+-bin-hadoop" | head -1 | sed -E 's/spark-//' | sed -E 's/-bin-hadoop//')

# Verificamos si se logró obtener la versión; de lo contrario, usamos una por defecto
if [ -z "$SPARK_VERSION" ]; then
    echo "No se pudo detectar la versión automáticamente. Usando la versión de respaldo 4.1.1..."
    SPARK_VERSION="4.1.1"
else
    echo "¡Última versión detectada con éxito: $SPARK_VERSION!"
fi

# Variables de descarga
SPARK_FILE="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
SPARK_DIR_NAME="spark-${SPARK_VERSION}-bin-hadoop3"
DOWNLOAD_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_FILE}"

echo "Descargando Apache Spark versión ${SPARK_VERSION}..."
cd $HOME
wget -c $DOWNLOAD_URL -O $SPARK_FILE

echo "Descomprimiendo y moviendo el paquete de Spark..."
tar -zxvf $SPARK_FILE -C $HOME
sudo rm -rf /opt/spark
sudo mv $HOME/$SPARK_DIR_NAME /opt/spark
# Opcional: Borramos el instalador para no dejar basura en tu sistema
rm $HOME/$SPARK_FILE

echo "Configurando variables de entorno en ~/.bashrc..."
# Eliminamos configuraciones previas para no duplicar líneas si corres el script varias veces
sed -i '/HADOOP_HOME/d' ~/.bashrc
sed -i '/SPARK_HOME/d' ~/.bashrc
sed -i '/PYSPARK/d' ~/.bashrc

echo 'export HADOOP_HOME=/usr/local/hadoop' >> ~/.bashrc
echo 'export SPARK_HOME=/opt/spark' >> ~/.bashrc
echo 'export PATH=$PATH:$SPARK_HOME/bin' >> ~/.bashrc
echo 'export PYSPARK_PYTHON=python3' >> ~/.bashrc
echo 'export PYSPARK_DRIVER_PYTHON=jupyter' >> ~/.bashrc
echo 'export PYSPARK_DRIVER_PYTHON_OPTS="notebook"' >> ~/.bashrc

echo "Creando carpeta de proyectos y ambiente virtual para Python..."
mkdir -p ~/spark_projects
cd ~/spark_projects
python3 -m venv venv
source venv/bin/activate

echo "Instalando paquetes requeridos en el ambiente virtual..."
pip install jupyter findspark pyspark

echo "=========================================================="
echo "¡Descarga de la última versión e instalación completadas!"
echo "=========================================================="
echo "Ejecuta lo siguiente para actualizar tu terminal:"
echo "source ~/.bashrc"
echo "source ~/spark_projects/venv/bin/activate"
echo "pyspark"
