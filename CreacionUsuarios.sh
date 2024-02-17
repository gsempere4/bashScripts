#!/bin/bash

##############################################################################################################
######################### Leemos el archivo CSV y guardamos en variables los valores #########################
##############################################################################################################

# Ruta donde se encuentra el archivo.csv
archivo="./alta.csv"
# Definir variable para el primer uidNumber
next_uidNumber=20001
# Definir variable para el primer gidNumber
next_gidNumber=10001

# Definir variables para LDAP
BASE_DN="dc=domsempere,dc=lan"  # Cambia esto por tu base DN
ADMIN_DN="cn=admin,$BASE_DN"  # Cambia esto por el DN del administrador de tu LDAP
ADMIN_PASS="Sempere4"        # Cambia esto por la contraseña del administrador de tu LDAP

# Función para buscar el GID del grupo de departamento
buscar_gid_departamento() {
    local departamento=$1
    local gid_result=$(ldapsearch -x -LLL -b "ou=$departamento,$BASE_DN" "(objectClass=posixGroup)" gidNumber 2>/dev/null | grep -oP '(?<=gidNumber: )[0-9]+')
    echo "$gid_result"
}

# Función para buscar el GID del grupo de sección
buscar_gid_seccion() {
    local seccion=$1
    local departamento=$2
    local gid_result=$(ldapsearch -x -LLL -b "ou=$seccion,ou=$departamento,$BASE_DN" "(objectClass=posixGroup)" gidNumber 2>/dev/null | grep -oP '(?<=gidNumber: )[0-9]+')
    echo "$gid_result"
}

# Verificar si el contenedor padre existe, de lo contrario, crearlo
search_result=$(ldapsearch -x -LLL -b "$BASE_DN" "(dc=domsempere)" 2>/dev/null)
if [ -z "$search_result" ]; then
    # Definir LDIF para el contenedor padre
    LDIF_BASE_DN=$(cat <<EOF
dn: $BASE_DN
dc: domsempere
objectClass: domain
EOF
)
    echo "$LDIF_BASE_DN" > basedn.ldif
    ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f basedn.ldif
fi

# IFS es necesario para que el comando read pueda interpretar correctamente el formato CSV y asignar
IFS=','
while  read -r Operacion Nombre Primer_apellido Login Seccion Departamento
do
    # Verificar si la línea actual NO es el encabezado
    if [ "$Departamento" != "Departamento" ]; then
        # Verificar si la OU de departamento ya existe
        search_result=$(ldapsearch -x -LLL -b "$BASE_DN" "(ou=$Departamento)" 2>/dev/null)
        if [ -z "$search_result" ]; then
            # Definir LDIF para la OU de departamento
            LDIF_DEPARTAMENTO=$(cat <<EOF
dn: ou=$Departamento,$BASE_DN
ou: $Departamento
objectClass: organizationalUnit
EOF
)
            echo "$LDIF_DEPARTAMENTO" > departamento.ldif
            ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f departamento.ldif
        fi

        # Verificar si la OU de sección ya existe dentro del departamento
        search_result=$(ldapsearch -x -LLL -b "ou=$Seccion,ou=$Departamento,$BASE_DN" "(ou=$Seccion)" 2>/dev/null)
        if [ -z "$search_result" ]; then
            # Definir LDIF para la OU de sección
            LDIF_SECCION=$(cat <<EOF
dn: ou=$Seccion,ou=$Departamento,$BASE_DN
ou: $Seccion
objectClass: organizationalUnit
EOF
)
            echo "$LDIF_SECCION" > seccion.ldif
            ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f seccion.ldif
        fi

        # Crear el grupo dentro de la OU de sección comprobando que el encabezado no se cree como grupo
        if [ "$Seccion" != "Seccion" ]; then
            nombre_grupo_seccion="g$Seccion"
            search_result=$(ldapsearch -x -LLL -b "ou=$Seccion,ou=$Departamento,$BASE_DN" "(cn=$nombre_grupo_seccion)" 2>/dev/null)
            if [ -z "$search_result" ]; then
                # Definir LDIF para el grupo dentro de la OU de sección
                LDIF_GRUPO_SECCION=$(cat <<EOF
dn: cn=$nombre_grupo_seccion,ou=$Seccion,ou=$Departamento,$BASE_DN
cn: $nombre_grupo_seccion
objectClass: posixGroup
gidNumber: $next_gidNumber
EOF
)
                echo "$LDIF_GRUPO_SECCION" > grupo_seccion.ldif
                ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f grupo_seccion.ldif
                ((next_gidNumber++))
            fi
        fi

        # Crear el grupo dentro de la OU de departamento
        nombre_grupo_departamento="g$Departamento"
        search_result=$(ldapsearch -x -LLL -b "ou=$Departamento,$BASE_DN" "(cn=$nombre_grupo_departamento)" 2>/dev/null)
        if [ -z "$search_result" ]; then
            # Definir LDIF para el grupo dentro de la OU de departamento
            LDIF_GRUPO_DEPARTAMENTO=$(cat <<EOF
dn: cn=$nombre_grupo_departamento,ou=$Departamento,$BASE_DN
cn: $nombre_grupo_departamento
objectClass: posixGroup
gidNumber: $next_gidNumber
EOF
)
            echo "$LDIF_GRUPO_DEPARTAMENTO" > grupo_departamento.ldif
            ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f grupo_departamento.ldif
            ((next_gidNumber++))
        fi

        # Obtener el GID del grupo de sección
        gid_seccion=$(buscar_gid_seccion "$Seccion" "$Departamento")

        # Crear usuario y establecer la contraseña cifrada como "Usuario123"
        if [ "$Login" != "Login" ]; then
            # Generar el hash de contraseña
            hashed_password=$(slappasswd -s "Usuario123")
            # Definir LDIF para el usuario
            LDIF_USUARIO=$(cat <<EOF
dn: uid=$Login,ou=$Seccion,ou=$Departamento,$BASE_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: $Nombre $Primer_apellido
sn: $Primer_apellido
uid: $Login
uidNumber: $next_uidNumber
gidNumber: $gid_seccion
homeDirectory: /srv/perfilesMoviles/$Login
userPassword: $hashed_password
EOF
)
            echo "$LDIF_USUARIO" > usuario.ldif
            ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f usuario.ldif
            ((next_uidNumber++))
        fi
    fi

done < "$archivo"