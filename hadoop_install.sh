#!/bin/bash

# ==========================================
# SCRIPT DE INSTALACIÓN AUTOMÁTICA DE HADOOP
# Adaptado para Ubuntu 20.04/22.04/24.04
# Basado en tu script de Fedora
# ==========================================

# Variables de versión (Mismas que tu script original)
HADOOP_VER="3.4.2"
HADOOP_URL="https://downloads.apache.org/hadoop/common/hadoop-$HADOOP_VER/hadoop-$HADOOP_VER.tar.gz"

# Ruta estándar en Ubuntu para OpenJDK 11 (amd64)
JAVA_HOME_PATH="/usr/lib/jvm/java-11-openjdk-amd64"
INSTALL_DIR="/usr/local/hadoop"
HADOOP_USER="hadoop"

# Comprobar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root (sudo)."
  exit
fi

echo ">>> 1. Actualizando sistema e instalando dependencias (apt)..."
apt update && apt upgrade -y
# Instalamos dependencias equivalentes en Ubuntu
apt install -y openjdk-11-jdk openssh-server pdsh wget tar hostname

echo ">>> 2. Configurando servicios del sistema (SSH y Firewall)..."
# Iniciar SSH
systemctl enable --now ssh

# Configurar Firewall (Ubuntu usa UFW, no firewalld)
if ufw status | grep -q "Status: active"; then
    echo "UFW está activo. Abriendo puertos de Hadoop..."
    ufw allow 9870/tcp # HDFS Web UI
    ufw allow 9000/tcp # HDFS IPC
    ufw allow 8088/tcp # YARN Web UI
    ufw allow 8042/tcp # NodeManager UI
    ufw reload
else
    echo "UFW no está activo, saltando configuración de puertos."
fi

echo ">>> 3. Creando usuario '$HADOOP_USER'..."
if id "$HADOOP_USER" &>/dev/null; then
    echo "El usuario ya existe."
else
    # En Ubuntu/Debian usamos adduser o useradd con flags específicos
    useradd -r -m -d /home/$HADOOP_USER -s /bin/bash $HADOOP_USER
    echo "Usuario creado."
fi

# Asignar contraseña al usuario hadoop (opcional pero recomendado en Ubuntu)
# echo "$HADOOP_USER:hadoop" | chpasswd

echo ">>> 4. Configurando SSH sin contraseña para '$HADOOP_USER'..."
# Ejecutamos los comandos como el usuario hadoop
sudo -u $HADOOP_USER bash -c "if [ ! -f ~/.ssh/id_rsa ]; then ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa; fi"
sudo -u $HADOOP_USER bash -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
sudo -u $HADOOP_USER bash -c "chmod 0600 ~/.ssh/authorized_keys"

# Escanear localhost para known_hosts
sudo -u $HADOOP_USER bash -c "ssh-keyscan -H localhost >> ~/.ssh/known_hosts 2>/dev/null"
sudo -u $HADOOP_USER bash -c "ssh-keyscan -H 0.0.0.0 >> ~/.ssh/known_hosts 2>/dev/null"
sudo -u $HADOOP_USER bash -c "ssh-keyscan -H $(hostname) >> ~/.ssh/known_hosts 2>/dev/null"

echo ">>> 5. Descargando e instalando Hadoop $HADOOP_VER..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Hadoop ya está instalado en $INSTALL_DIR."
else
    cd /tmp
    wget -nc $HADOOP_URL
    tar -xzf hadoop-$HADOOP_VER.tar.gz
    mv hadoop-$HADOOP_VER $INSTALL_DIR
    echo "Hadoop instalado."
fi
chown -R $HADOOP_USER:$HADOOP_USER $INSTALL_DIR

echo ">>> 6. Configurando variables de entorno (.bashrc)..."
BASHRC="/home/$HADOOP_USER/.bashrc"
if ! grep -q "HADOOP_HOME" $BASHRC; then
    cat <<EOT >> $BASHRC

# Hadoop Variables
export JAVA_HOME=$JAVA_HOME_PATH
export HADOOP_HOME=$INSTALL_DIR
export HADOOP_INSTALL=\$HADOOP_HOME
export HADOOP_MAPRED_HOME=\$HADOOP_HOME
export HADOOP_COMMON_HOME=\$HADOOP_HOME
export HADOOP_HDFS_HOME=\$HADOOP_HOME
export YARN_HOME=\$HADOOP_HOME
export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_HOME/lib/native
export HADOOP_OPTS="-Djava.library.path=\$HADOOP_HOME/lib/native"
export PATH=\$PATH:\$HADOOP_HOME/sbin:\$HADOOP_HOME/bin
# PDSH en Ubuntu requiere especificar ssh explícitamente
export PDSH_RCMD_TYPE=ssh
EOT
fi

echo ">>> 7. Configurando Archivos XML..."

# --- hadoop-env.sh ---
echo "export JAVA_HOME=$JAVA_HOME_PATH" >> $INSTALL_DIR/etc/hadoop/hadoop-env.sh

# --- core-site.xml ---
cat > $INSTALL_DIR/etc/hadoop/core-site.xml <<EOL
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
</configuration>
EOL

# --- hdfs-site.xml ---
mkdir -p $INSTALL_DIR/hdfs/namenode
mkdir -p $INSTALL_DIR/hdfs/datanode
chown -R $HADOOP_USER:$HADOOP_USER $INSTALL_DIR/hdfs

cat > $INSTALL_DIR/etc/hadoop/hdfs-site.xml <<EOL
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://$INSTALL_DIR/hdfs/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://$INSTALL_DIR/hdfs/datanode</value>
    </property>
</configuration>
EOL

# --- mapred-site.xml ---
cat > $INSTALL_DIR/etc/hadoop/mapred-site.xml <<EOL
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value>
    </property>
</configuration>
EOL

# --- yarn-site.xml ---
cat > $INSTALL_DIR/etc/hadoop/yarn-site.xml <<EOL
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_MAPRED_HOME</value>
    </property>
</configuration>
EOL

echo ">>> 8. Formateando el NameNode..."
if [ -z "$(ls -A $INSTALL_DIR/hdfs/namenode)" ]; then
   sudo -u $HADOOP_USER $INSTALL_DIR/bin/hdfs namenode -format
else
   echo "NameNode ya formateado."
fi

echo ">>> 9. Creando comandos rápidos..."
# Script Inicio
cat > /usr/local/bin/iniciar-hadoop <<EOF
#!/bin/bash
echo "Iniciando Hadoop en Ubuntu..."
sudo -u $HADOOP_USER $INSTALL_DIR/sbin/start-dfs.sh
sudo -u $HADOOP_USER $INSTALL_DIR/sbin/start-yarn.sh
echo "Hadoop iniciado. Web UI: http://localhost:9870"
EOF
chmod +x /usr/local/bin/iniciar-hadoop

# Script Parada
cat > /usr/local/bin/detener-hadoop <<EOF
#!/bin/bash
echo "Deteniendo Hadoop..."
sudo -u $HADOOP_USER $INSTALL_DIR/sbin/stop-yarn.sh
sudo -u $HADOOP_USER $INSTALL_DIR/sbin/stop-dfs.sh
EOF
chmod +x /usr/local/bin/detener-hadoop

echo "¡Instalación en Ubuntu completada! Ejecuta 'iniciar-hadoop' para comenzar."
