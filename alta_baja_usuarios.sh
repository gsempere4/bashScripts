#!/bin/bash
##############################################################################################################
######################### Leemos el archivo CSV y guardamos en variables los valores #########################
##############################################################################################################
# Ruta donde se encuentra el archivo.csv
archivoA="/srv/administracioUsuaris/alta.csv"  # El nombre del archivo que dara de alta a espos usuarios
archivoB="/srv/administracioUsuaris/baja.csv"  # El nombre del archivo que dara de baja a esos usuarios
# Definir variable para el primer uidNumber
next_uidNumber=10001
# Definir variable para el primer gidNumber
next_gidNumber=20001
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
#si el archivoA existe empezara a realizar las creaciones de OU,Grupos y Usuarios si no existen
if [ -f "$archivoA" ]
then
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
        # Verificar si el usuario ya existe
        search_user=$(ldapsearch -x -LLL -b "uid=$Login,ou=$Seccion,ou=$Departamento,$BASE_DN" uid 2>/dev/null)
        if [ -n "$search_user" ]; then
            if [ "$Operacion" == "Baja" ]; then
                # Eliminar usuario
                ldapdelete -x -D "$ADMIN_DN" -w "$ADMIN_PASS" "uid=$Login,ou=$Seccion,ou=$Departamento,$BASE_DN"
                echo "Usuario $Login eliminado."
            else
                echo "El usuario $Login ya existe. Operación no realizada."
            fi
        else
            if [ "$Operacion" == "Alta" ]; then
                # Crear usuario y establecer la contraseña cifrada como "Usuario123"
                # Obtener el GID del grupo de sección
                gid_seccion=$(buscar_gid_seccion "$Seccion" "$Departamento")
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
                echo "Usuario $Login creado."
            else
                echo "El usuario $Login no existe. Operación no realizada."
            fi
        fi
    fi
done < "$archivoA"
fi
if [ -f "$archivoB" ]
then
# IFS es necesario para que el comando read pueda interpretar correctamente el formato CSV y asignar
IFS=','
while  read -r Operacion Nombre Primer_apellido Login Seccion Departamento
do
      # Verificar si el usuario ya existe
        search_user=$(ldapsearch -x -LLL -b "uid=$Login,ou=$Seccion,ou=$Departamento,$BASE_DN" uid 2>/dev/null)
        if [ -n "$search_user" ]; then
            if [ "$Operacion" == "Baja" ]; then
                # Eliminar usuario
                ldapdelete -x -D "$ADMIN_DN" -w "$ADMIN_PASS" "uid=$Login,ou=$Seccion,ou=$Departamento,$BASE_DN"
                echo "Usuario $Login eliminado."
            else
                echo "El usuario $Login ya existe. Operación no realizada."
            fi
  	fi
done < "$archivoB"
fi
# Guardar la fecha y hora actual en el formato deseado
fecha_hora=$(date +"%Y%m%d_%H%M%S")
# Crear la subcarpeta historic si aún no existe
subcarpeta="/srv/administracioUsuaris/historico"
if [ ! -d "$subcarpeta" ]; then
    mkdir -p "$subcarpeta"
fi
# Mover el archivo CSV procesado a la carpeta de historial con el nombre adecuado
if [ -f "$archivo" ]; then
    mv "$archivoA" "/srv/administracioUsuaris/historico/"$fecha_hora"_alta.csv"
elif [ -f "$archivoB" ]; then
    mv "$archivoB" "/srv/administracioUsuaris/historico/"$fecha_hora"_baja.csv"
fi