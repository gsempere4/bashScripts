

#!/bin/bash
##############################################################################################################
######################### Leemos el archivo CSV y guardamos en variables los valores #########################
##############################################################################################################

# Ruta donde se encuentra el archivo.csv
#archivo="/srv/administracioUsuaris/alta_baja_usuarios.csv"
archivo="./alta.csv"

# Definir variable para el primer gidNumber
next_gidNumber=10001

# Leemos el archivo CSV línea a línea
# IFS es necesario para que el comando read pueda interpretar correctamente el formato CSV y asignar
IFS=','
while  read -r Operacion Nombre Primer_apellido Login Seccion Departamento
do
# Definir variables
    BASE_DN="dc=domsempere,dc=lan"  # Cambia esto por tu base DN
    ADMIN_DN="cn=admin,$BASE_DN"  # Cambia esto por el DN del administrador de tu LDAP
    ADMIN_PASS="Sempere4"        # Cambia esto por la contraseña del administrador de tu LDAP
    
# Verificar si el valor de la variable es "Departamento"
if [ "$Departamento" = "Departamento" ]
then
    echo "La variable DEPARTAMENTO tiene el valor 'Departamento', no se realiza ninguna acción." >> /dev/null
else
    # Realiza la búsqueda para verificar si la OU de departamento ya existe
    search_result=$(ldapsearch -x -LLL -b "$BASE_DN" "(ou=$Departamento)")
    # Verifica si no se encontraron resultados, entonces crea la OU de departamento
    if [ -z "$search_result" ]; then
        echo "La OU '$Departamento' no existe."
        # Definir LDIF para la OU de departamento
        LDIF_DEPARTAMENTO=$(cat <<EOF
dn: ou=$Departamento,$BASE_DN
ou: $Departamento
objectClass: organizationalUnit
EOF
)
        echo "$LDIF_DEPARTAMENTO" > departamento.ldif
        ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f departamento.ldif
        # Verificar el resultado
        if [ $? -eq 0 ]; then
            echo "OU de departamento creada exitosamente: ou=$Departamento,$BASE_DN"
        fi
    else
        echo "La OU '$Departamento' ya existe."
    fi
    
    # Verificar si el valor de la variable es "Seccion"
    if [ "$Seccion" = "Seccion" ]; then
        echo "La variable SECCION tiene el valor 'Seccion', no se realiza ninguna acción." >> /dev/null
    else
        # Realiza la búsqueda para verificar si la OU de sección ya existe dentro del departamento
        search_result=$(ldapsearch -x -LLL -b "ou=$Departamento,$BASE_DN" "(ou=$Seccion)")
        # Verifica si no se encontraron resultados, entonces crea la OU de sección
        if [ -z "$search_result" ]; then
            echo "La OU '$Seccion' no existe dentro del departamento '$Departamento'. Creando..."
            # Definir LDIF para la OU de sección
            LDIF_SECCION=$(cat <<EOF
dn: ou=$Seccion,ou=$Departamento,$BASE_DN
ou: $Seccion
objectClass: organizationalUnit
EOF
)
            echo "$LDIF_SECCION" > seccion.ldif
            ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f seccion.ldif
            # Verificar el resultado
            if [ $? -eq 0 ]; then
                echo "OU de sección creada exitosamente: ou=$Seccion,ou=$Departamento,$BASE_DN"
            fi
        else
            echo "La OU '$Seccion' ya existe dentro del departamento '$Departamento'."
        fi
    fi
    
    # Verificar si el valor de la variable es "Departamento"
    # Crear el grupo dentro de la OU de departamento
    if [ "$Departamento" != "Departamento" ]; then
        nombre_grupo="g$Departamento"
        search_result=$(ldapsearch -x -LLL -b "ou=$Departamento,$BASE_DN" "(cn=$nombre_grupo)")
        if [ -z "$search_result" ]; then
            echo "El grupo '$nombre_grupo' no existe dentro de la OU '$Departamento'. Creando..."
            # Definir LDIF para el grupo dentro de la OU de departamento
            LDIF_GRUPO=$(cat <<EOF
dn: cn=$nombre_grupo,ou=$Departamento,$BASE_DN
cn: $nombre_grupo
objectClass: posixGroup
gidNumber: $next_gidNumber
EOF
)
            echo "$LDIF_GRUPO" > grupo.ldif
            ldapadd -x -D "$ADMIN_DN" -w "$ADMIN_PASS" -f grupo.ldif
            # Verificar el resultado
            if [ $? -eq 0 ]; then
                echo "Grupo creado exitosamente: cn=$nombre_grupo,ou=$Departamento,$BASE_DN"
                ((next_gidNumber++))  # Incrementar el contador de gidNumber
            fi
        else
            echo "El grupo '$nombre_grupo' ya existe dentro de la OU '$Departamento'."
        fi
    fi
fi

done < "$archivo"
