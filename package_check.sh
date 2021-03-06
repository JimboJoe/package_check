#!/bin/bash

# Arguments du script
# --bash-mode	Mode bash, le script est autonome. Il ignore la valeur de $auto_remove
# --no-lxc	N'utilise pas la virtualisation en conteneur lxc. La virtualisation est utilisée par défaut si disponible.
# --build-lxc	Installe lxc et créer la machine si nécessaire. Incompatible avec --bash-mode en raison de la connexion ssh à valider lors du build.
# --force-install-ok	Force la réussite des installations, même si elles échouent. Permet d'effectuer les tests qui suivent même si l'installation a échouée.
# --help	Affiche l'aide du script

echo ""

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

source "$script_dir/sub_scripts/lxc_launcher.sh"
source "$script_dir/sub_scripts/testing_process.sh"
source /usr/share/yunohost/helpers

# Vérifie la connexion internet.
ping -q -c 2 yunohost.org > /dev/null 2>&1
if [ "$?" -ne 0 ]; then	# En cas d'échec de connexion, tente de pinger un autre domaine pour être sûr
	ping -q -c 2 framasoft.org > /dev/null 2>&1
	if [ "$?" -ne 0 ]; then	# En cas de nouvel échec de connexion. On considère que la connexion est down...
		ECHO_FORMAT "Impossible d'établir une connexion à internet.\n" "red"
		exit 1
	fi
fi

version_script="$(git ls-remote https://github.com/YunoHost/package_check | cut -f 1 | head -n1)"
if [ -e "$script_dir/package_version" ]
then
	if [ "$version_script" != "$(cat "$script_dir/package_version")" ]; then	# Si le dernier commit sur github ne correspond pas au commit enregistré, il y a une mise à jour.
		# Écrit le script de mise à jour, qui sera exécuté à la place de ce script, pour le remplacer et le relancer après.
		ECHO_FORMAT "Mise à jour de Package check...\n" "white" "bold"
		echo -e "#!/bin/bash\n" > "$script_dir/upgrade_script.sh"
		echo "git clone --quiet https://github.com/YunoHost/package_check \"$script_dir/upgrade\"" >> "$script_dir/upgrade_script.sh"
		echo "sudo cp -a \"$script_dir/upgrade/.\" \"$script_dir/.\"" >> "$script_dir/upgrade_script.sh"
		echo "sudo rm -r \"$script_dir/upgrade\"" >> "$script_dir/upgrade_script.sh"
		echo "echo \"$version_script\" > \"$script_dir/package_version\"" >> "$script_dir/upgrade_script.sh"
		echo "exec \"$script_dir/package_check.sh\" \"$*\"" >> "$script_dir/upgrade_script.sh"
		chmod +x "$script_dir/upgrade_script.sh"
		exec "$script_dir/upgrade_script.sh"	#Exécute le script de mise à jour.
	fi
else
	echo "$version_script" > "$script_dir/package_version"
fi

version_plinter="$(git ls-remote https://github.com/YunoHost/package_linter | cut -f 1 | head -n1)"
if [ -e "$script_dir/plinter_version" ]
then
	if [ "$version_plinter" != "$(cat "$script_dir/plinter_version")" ]; then	# Si le dernier commit sur github ne correspond pas au commit enregistré, il y a une mise à jour.
		ECHO_FORMAT "Mise à jour de package_linter..." "white" "bold"
		git clone --quiet https://github.com/YunoHost/package_linter "$script_dir/package_linter_tmp"
		sudo cp -a "$script_dir/package_linter_tmp/." "$script_dir/package_linter/."
		sudo rm -r "$script_dir/package_linter_tmp"
	fi
else	# Si le fichier de version n'existe pas, il est créé.
	echo "$version_plinter" > "$script_dir/plinter_version"
	ECHO_FORMAT "Installation de package_linter.\n" "white"
	git clone --quiet https://github.com/YunoHost/package_linter "$script_dir/package_linter"
fi
echo "$version_plinter" > "$script_dir/plinter_version"

notice=0
if [ "$#" -eq 0 ]
then
	echo "Le script prend en argument le package à tester."
	notice=1
fi

## Récupère les arguments
# --bash-mode
bash_mode=$(echo "$*" | grep -c -e "--bash-mode")	# bash_mode vaut 1 si l'argument est présent.
# --no-lxc
no_lxc=$(echo "$*" | grep -c -e "--no-lxc")	# no_lxc vaut 1 si l'argument est présent.
# --build-lxc
build_lxc=$(echo "$*" | grep -c -e "--build-lxc")	# build_lxc vaut 1 si l'argument est présent.
# --force-install-ok
force_install_ok=$(echo "$*" | grep -c -e "--force-install-ok")	# force-install-ok vaut 1 si l'argument est présent.
# --help
if [ "$notice" -eq 0 ]; then
	notice=$(echo "$*" | grep -c -e "--help")	# notice vaut 1 si l'argument est présent. Il affichera alors l'aide.
fi
arg_app=$(echo "$*" | sed 's/--bash-mode\|--no-lxc\|--build-lxc\|--force-install-ok//g' | sed 's/^ *\| *$//g')	# Supprime les arguments déjà lu pour ne garder que l'app. Et supprime les espaces au début et à la fin
# echo "arg_app=$arg_app."

if [ "$notice" -eq 1 ]; then
	echo -e "\nUsage:"
	echo "package_check.sh [--bash-mode] [--no-lxc] [--build-lxc] [--force-install-ok] [--help] \"check package\""
	echo -e "\n\t--bash-mode\t\tDo not ask for continue check. Ignore auto_remove."
	echo -e "\t--no-lxc\t\tDo not use a LXC container. You should use this option only on a test environnement."
	echo -e "\t--build-lxc\t\tInstall LXC and build the container if necessary."
	echo -e "\t--force-install-ok\tForce following test even if all install are failed."
	echo -e "\t--help\t\t\tDisplay this notice."
	exit 0
fi

USER_TEST=package_checker
PASSWORD_TEST=checker_pwd
PATH_TEST=/check
LXC_NAME=$(cat "$script_dir/sub_scripts/lxc_build.sh" | grep LXC_NAME= | cut -d '=' -f2)

if [ "$no_lxc" -eq 0 ]
then
	DOMAIN=$(sudo cat /var/lib/lxc/$LXC_NAME/rootfs/etc/yunohost/current_host)
else
	DOMAIN=$(sudo yunohost domain list -l 1 | cut -d" " -f 2)
fi
SOUS_DOMAIN="sous.$DOMAIN"

if [ "$no_lxc" -eq 0 ]
then	# Si le conteneur lxc est utilisé
	lxc_ok=0
	# Vérifie la présence du virtualisateur en conteneur LXC
	if dpkg-query -W -f '${Status}' "lxc" 2>/dev/null | grep -q "ok installed"; then
		if sudo lxc-ls | grep -q "$LXC_NAME"; then	# Si lxc est installé, vérifie la présence de la machine $LXC_NAME
			lxc_ok=1
		fi
	fi
	if [ "$lxc_ok" -eq 0 ]
	then
		if [ "$build_lxc" -eq 1 ]
		then
			"$script_dir/sub_scripts/lxc_build.sh"	# Lance la construction de la machine virtualisée.
		else
			ECHO_FORMAT "Lxc n'est pas installé, ou la machine $LXC_NAME n'est pas créée.\n" "red"
			ECHO_FORMAT "Utilisez le script 'lxc_build.sh' pour installer lxc et créer la machine.\n" "red"
			ECHO_FORMAT "Ou utilisez l'argument --no-lxc\n" "red"
			exit 1
		fi
	fi
	# Stoppe toute activité éventuelle du conteneur, en cas d'arrêt incorrect précédemment
	LXC_STOP
	LXC_TURNOFF
else	# Vérifie l'utilisateur et le domain si lxc n'est pas utilisé.
	# Vérifie l'existence de l'utilisateur de test
	echo -e "\nVérification de l'existence de l'utilisateur de test..."
	if ! ynh_user_exists "$USER_TEST"
	then	# Si il n'existe pas, il faut le créer.
		USER_TEST_CLEAN=${USER_TEST//"_"/""}
		sudo yunohost user create --firstname "$USER_TEST_CLEAN" --mail "$USER_TEST_CLEAN@$DOMAIN" --lastname "$USER_TEST_CLEAN" --password "$PASSWORD_TEST" "$USER_TEST"
		if [ "$?" -ne 0 ]; then
			ECHO_FORMAT "La création de l'utilisateur de test a échoué. Impossible de continuer.\n" "red"
			exit 1
		fi
	fi

	# Vérifie l'existence du sous-domaine de test
	echo "Vérification de l'existence du domaine de test..."
	if [ "$(sudo yunohost domain list | grep -c "$SOUS_DOMAIN")" -eq 0 ]; then	# Si il n'existe pas, il faut le créer.
		sudo yunohost domain add "$SOUS_DOMAIN"
		if [ "$?" -ne 0 ]; then
			ECHO_FORMAT "La création du sous-domain de test a échoué. Impossible de continuer.\n" "red"
			exit 1
		fi
	fi
fi

# Vérifie le type d'emplacement du package à tester
echo "Récupération du package à tester."
rm -rf "$script_dir"/*_check
GIT_PACKAGE=0
if echo "$arg_app" | grep -Eq "https?:\/\/"
then
	GIT_PACKAGE=1
	git clone $arg_app "$script_dir/$(basename "$arg_app")_check"
else
	# Si c'est un dossier local, il est copié dans le dossier du script.
	sudo cp -a --remove-destination "$arg_app" "$script_dir/$(basename "$arg_app")_check"
fi
APP_CHECK="$script_dir/$(basename "$arg_app")_check"
if [ "$no_lxc" -eq 0 ]
then	# En cas d'exécution dans LXC, l'app sera dans le home de l'user LXC.
	APP_PATH_YUNO="$(basename "$arg_app")_check"
else
	APP_PATH_YUNO="$APP_CHECK"
fi

if [ ! -d "$APP_CHECK" ]; then
	ECHO_FORMAT "Le dossier de l'application a tester est introuvable...\n" "red"
	exit 1
fi
sudo rm -rf "$APP_CHECK/.git"	# Purge des fichiers de git

# Vérifie l'existence du fichier check_process
check_file=1
if [ ! -e "$APP_CHECK/check_process" ]; then
	ECHO_FORMAT "\nImpossible de trouver le fichier check_process pour procéder aux tests.\n" "red"
	ECHO_FORMAT "Package check va être utilisé en mode dégradé.\n" "lyellow"
	check_file=0
fi



TEST_RESULTS () {
	ECHO_FORMAT "\n\nPackage linter: "
	if [ "$GLOBAL_LINTER" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_LINTER" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi
	ECHO_FORMAT "Installation: "
	if [ "$GLOBAL_CHECK_SETUP" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_SETUP" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Suppression: "
	if [ "$GLOBAL_CHECK_REMOVE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_REMOVE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation en sous-dossier: "
	if [ "$GLOBAL_CHECK_SUB_DIR" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_SUB_DIR" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Suppression depuis sous-dossier: "
	if [ "$GLOBAL_CHECK_REMOVE_SUBDIR" -eq 1 ]; then
		ECHO_FORMAT "\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_REMOVE_SUBDIR" -eq -1 ]; then
		ECHO_FORMAT "\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation à la racine: "
	if [ "$GLOBAL_CHECK_ROOT" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_ROOT" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Suppression depuis racine: "
	if [ "$GLOBAL_CHECK_REMOVE_ROOT" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_REMOVE_ROOT" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Upgrade: "
	if [ "$GLOBAL_CHECK_UPGRADE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_UPGRADE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation privée: "
	if [ "$GLOBAL_CHECK_PRIVATE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PRIVATE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation publique: "
	if [ "$GLOBAL_CHECK_PUBLIC" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PUBLIC" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Installation multi-instance: "
	if [ "$GLOBAL_CHECK_MULTI_INSTANCE" -eq 1 ]; then
		ECHO_FORMAT "\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_MULTI_INSTANCE" -eq -1 ]; then
		ECHO_FORMAT "\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Mauvais utilisateur: "
	if [ "$GLOBAL_CHECK_ADMIN" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_ADMIN" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Erreur de domaine: "
	if [ "$GLOBAL_CHECK_DOMAIN" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_DOMAIN" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Correction de path: "
	if [ "$GLOBAL_CHECK_PATH" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PATH" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Port déjà utilisé: "
	if [ "$GLOBAL_CHECK_PORT" -eq 1 ]; then
		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_PORT" -eq -1 ]; then
		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
	fi

# 	ECHO_FORMAT "Source corrompue: "
# 	if [ "$GLOBAL_CHECK_CORRUPT" -eq 1 ]; then
# 		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
# 	elif [ "$GLOBAL_CHECK_CORRUPT" -eq -1 ]; then
# 		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
# 	else
# 		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
# 	fi

# 	ECHO_FORMAT "Erreur de téléchargement de la source: "
# 	if [ "$GLOBAL_CHECK_DL" -eq 1 ]; then
# 		ECHO_FORMAT "\tSUCCESS\n" "lgreen"
# 	elif [ "$GLOBAL_CHECK_DL" -eq -1 ]; then
# 		ECHO_FORMAT "\tFAIL\n" "lred"
# 	else
# 		ECHO_FORMAT "\tNot evaluated.\n" "white"
# 	fi

# 	ECHO_FORMAT "Dossier déjà utilisé: "
# 	if [ "$GLOBAL_CHECK_FINALPATH" -eq 1 ]; then
# 		ECHO_FORMAT "\t\t\tSUCCESS\n" "lgreen"
# 	elif [ "$GLOBAL_CHECK_FINALPATH" -eq -1 ]; then
# 		ECHO_FORMAT "\t\t\tFAIL\n" "lred"
# 	else
# 		ECHO_FORMAT "\t\t\tNot evaluated.\n" "white"
# 	fi

	ECHO_FORMAT "Backup: "
	if [ "$GLOBAL_CHECK_BACKUP" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_BACKUP" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi

	ECHO_FORMAT "Restore: "
	if [ "$GLOBAL_CHECK_RESTORE" -eq 1 ]; then
		ECHO_FORMAT "\t\t\t\tSUCCESS\n" "lgreen"
	elif [ "$GLOBAL_CHECK_RESTORE" -eq -1 ]; then
		ECHO_FORMAT "\t\t\t\tFAIL\n" "lred"
	else
		ECHO_FORMAT "\t\t\t\tNot evaluated.\n" "white"
	fi
	ECHO_FORMAT "\t\t    Notes de résultats: $note/$tnote - " "white" "bold"
	if [ "$note" -gt 0 ]
	then
		note=$(( note * 20 / tnote ))
	fi
		if [ "$note" -le 5 ]; then
			color_note="red"
			typo_note="bold"
			smiley=":'("	# La contribution à Shasha. Qui m'a forcé à ajouté les smiley sous la contrainte ;)
		elif [ "$note" -le 10 ]; then
			color_note="red"
			typo_note=""
			smiley=":("
		elif [ "$note" -le 15 ]; then
			color_note="lyellow"
			typo_note=""
			smiley=":s"
		elif [ "$note" -gt 15 ]; then
			color_note="lgreen"
			typo_note=""
			smiley=":)"
		fi
		if [ "$note" -ge 20 ]; then
			color_note="lgreen"
			typo_note="bold"
			smiley="\o/"
		fi
	ECHO_FORMAT "$note/20 $smiley\n" "$color_note" "$typo_note"
	ECHO_FORMAT "\t   Ensemble de tests effectués: $tnote/17\n\n" "white" "bold"
}

INIT_VAR() {
	GLOBAL_LINTER=0
	GLOBAL_CHECK_SETUP=0
	GLOBAL_CHECK_SUB_DIR=0
	GLOBAL_CHECK_ROOT=0
	GLOBAL_CHECK_REMOVE=0
	GLOBAL_CHECK_REMOVE_SUBDIR=0
	GLOBAL_CHECK_REMOVE_ROOT=0
	GLOBAL_CHECK_UPGRADE=0
	GLOBAL_CHECK_BACKUP=0
	GLOBAL_CHECK_RESTORE=0
	GLOBAL_CHECK_PRIVATE=0
	GLOBAL_CHECK_PUBLIC=0
	GLOBAL_CHECK_MULTI_INSTANCE=0
	GLOBAL_CHECK_ADMIN=0
	GLOBAL_CHECK_DOMAIN=0
	GLOBAL_CHECK_PATH=0
	GLOBAL_CHECK_CORRUPT=0
	GLOBAL_CHECK_DL=0
	GLOBAL_CHECK_PORT=0
	GLOBAL_CHECK_FINALPATH=0
	IN_PROCESS=0
	MANIFEST=0
	CHECKS=0
	auto_remove=1
	install_pass=0
	note=0
	tnote=0
	all_test=0
	use_curl=0

	MANIFEST_DOMAIN="null"
	MANIFEST_PATH="null"
	MANIFEST_USER="null"
	MANIFEST_PUBLIC="null"
	MANIFEST_PUBLIC_public="null"
	MANIFEST_PUBLIC_private="null"
	MANIFEST_PASSWORD="null"
	MANIFEST_PORT="null"

	pkg_linter=0
	setup_sub_dir=0
	setup_root=0
	setup_nourl=0
	setup_private=0
	setup_public=0
	upgrade=0
	backup_restore=0
	multi_instance=0
	wrong_user=0
	wrong_path=0
	incorrect_path=0
	corrupt_source=0
	fail_download_source=0
	port_already_use=0
	final_path_already_use=0
}

INIT_VAR
echo -n "" > "$COMPLETE_LOG"	# Initialise le fichier de log
echo -n "" > "$RESULT"	# Initialise le fichier des résulats d'analyse
if [ "$no_lxc" -eq 0 ]; then
	LXC_INIT
fi

if [ "$check_file" -eq 1 ]
then # Si le fichier check_process est trouvé
	## Parsing du fichier check_process de manière séquentielle.
	echo "Parsing du fichier check_process"
	while read <&4 LIGNE
	do
		LIGNE=$(echo $LIGNE | sed 's/^ *"//g')	# Efface les espaces en début de ligne
		if [ "${LIGNE:0:1}" == "#" ]; then
			# Ligne de commentaire, ignorée.
			continue
		fi
		if echo "$LIGNE" | grep -q "^auto_remove="; then	# Indication d'auto remove
			auto_remove=$(echo "$LIGNE" | cut -d '=' -f2)
		fi
		if echo "$LIGNE" | grep -q "^;;"; then	# Début d'un scénario de test
			if [ "$IN_PROCESS" -eq 1 ]; then	# Un scénario est déjà en cours. Donc on a atteind la fin du scénario.
				TESTING_PROCESS
				TEST_RESULTS
				INIT_VAR
				if [ "$bash_mode" -ne 1 ]; then
					read -p "Appuyer sur une touche pour démarrer le scénario de test suivant..." < /dev/tty
				fi
			fi
			PROCESS_NAME=${LIGNE#;; }
			IN_PROCESS=1
			MANIFEST=0
			CHECKS=0
		fi
		if [ "$IN_PROCESS" -eq 1 ]
		then	# Analyse des arguments du scenario de test
			if echo "$LIGNE" | grep -q "^; Manifest"; then	# Arguments du manifest
				MANIFEST=1
				MANIFEST_ARGS=""	# Initialise la chaine des arguments d'installation
			fi
			if echo "$LIGNE" | grep -q "^; Checks"; then	# Tests à effectuer
				MANIFEST=0
				CHECKS=1
			fi
			if [ "$MANIFEST" -eq 1 ]
			then	# Analyse des arguments du manifest
				if echo "$LIGNE" | grep -q "="; then
					if echo "$LIGNE" | grep -q "(DOMAIN)"; then	# Domaine dans le manifest
						MANIFEST_DOMAIN=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au domaine
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PATH)"; then	# Path dans le manifest
						MANIFEST_PATH=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au path
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(USER)"; then	# User dans le manifest
						MANIFEST_USER=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant à l'utilisateur
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PUBLIC"; then	# Accès public/privé dans le manifest
						MANIFEST_PUBLIC=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant à l'accès public ou privé
						MANIFEST_PUBLIC_public=$(echo "$LIGNE" | grep -o "|public=[a-Z]*" | cut -d "=" -f2)	# Récupère la valeur pour un accès public.
						MANIFEST_PUBLIC_private=$(echo "$LIGNE" | grep -o "|private=[a-Z]*" | cut -d "=" -f2)	# Récupère la valeur pour un accès privé.
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PASSWORD)"; then	# Password dans le manifest
						MANIFEST_PASSWORD=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au mot de passe
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
					if echo "$LIGNE" | grep -q "(PORT)"; then	# Port dans le manifest
						MANIFEST_PORT=$(echo "$LIGNE" | cut -d '=' -f1)	# Récupère la clé du manifest correspondant au port
						LIGNE=$(echo "$LIGNE" | cut -d '(' -f1)	# Retire l'indicateur de clé de manifest à la fin de la ligne
					fi
# 					if [ "${#MANIFEST_ARGS}" -gt 0 ]; then	# Si il y a déjà des arguments
# 						MANIFEST_ARGS="$MANIFEST_ARGS&"	#, précède de &
# 					fi
					MANIFEST_ARGS="$MANIFEST_ARGS$(echo $LIGNE | sed 's/^ *\| *$\|\"//g')&"	# Ajoute l'argument du manifest, en retirant les espaces de début et de fin ainsi que les guillemets.
				fi
			fi
			if [ "$CHECKS" -eq 1 ]
			then	# Analyse des tests à effectuer sur ce scenario.
				if echo "$LIGNE" | grep -q "^pkg_linter="; then	# Test d'installation en sous-dossier
					pkg_linter=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$pkg_linter" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_sub_dir="; then	# Test d'installation en sous-dossier
					setup_sub_dir=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_sub_dir" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_root="; then	# Test d'installation à la racine
					setup_root=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_root" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_nourl="; then	# Test d'installation sans accès par url
					setup_nourl=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_nourl" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_private="; then	# Test d'installation en privé
					setup_private=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_private" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^setup_public="; then	# Test d'installation en public
					setup_public=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$setup_public" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^upgrade="; then	# Test d'upgrade
					upgrade=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$upgrade" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^backup_restore="; then	# Test de backup et restore
					backup_restore=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$backup_restore" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^multi_instance="; then	# Test d'installation multiple
					multi_instance=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$multi_instance" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^wrong_user="; then	# Test d'erreur d'utilisateur
					wrong_user=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$wrong_user" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^wrong_path="; then	# Test d'erreur de path ou de domaine
					wrong_path=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$wrong_path" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^incorrect_path="; then	# Test d'erreur de forme de path
					incorrect_path=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$incorrect_path" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^corrupt_source="; then	# Test d'erreur sur source corrompue
					corrupt_source=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$corrupt_source" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^fail_download_source="; then	# Test d'erreur de téléchargement de la source
					fail_download_source=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$fail_download_source" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^port_already_use="; then	# Test d'erreur de port
					port_already_use=$(echo "$LIGNE" | cut -d '=' -f2)
					if echo "$LIGNE" | grep -q "([0-9]*)"
					then	# Le port est mentionné ici.
						MANIFEST_PORT="$(echo "$LIGNE" | cut -d '(' -f2 | cut -d ')' -f1)"	# Récupère le numéro du port; Le numéro de port est précédé de # pour indiquer son absence du manifest.
						port_already_use=${port_already_use:0:1}	# Garde uniquement la valeur de port_already_use
					fi
					if [ "$port_already_use" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
				if echo "$LIGNE" | grep -q "^final_path_already_use="; then	# Test sur final path déjà utilisé.
					final_path_already_use=$(echo "$LIGNE" | cut -d '=' -f2)
					if [ "$final_path_already_use" -eq 1 ]; then
						all_test=$((all_test+1))
					fi
				fi
			fi
		fi
	done 4< "$APP_CHECK/check_process"	# Utilise le descripteur de fichier 4. Car le descripteur 1 est utilisé par d'autres boucles while read dans ces scripts.
else	# Si le fichier check_process n'a pas été trouvé, fonctionne en mode dégradé.
	python "$script_dir/sub_scripts/ci/maniackc.py" "$APP_CHECK/manifest.json" > "$script_dir/manifest_extract" # Extrait les infos du manifest avec le script de Bram
	pkg_linter=1
	setup_sub_dir=1
	setup_root=1
	upgrade=1
	backup_restore=1
	multi_instance=1
	wrong_user=1
	wrong_path=1
	incorrect_path=1
	all_test=$((all_test+9))
	while read LIGNE
	do
		if echo "$LIGNE" | grep -q ":ynh.local"; then
			MANIFEST_DOMAIN=$(echo "$LIGNE" | grep ":ynh.local" | cut -d ':' -f1)	# Garde uniquement le nom de la clé.
		fi
		if echo "$LIGNE" | grep -q "path:"; then
			MANIFEST_PATH=$(echo "$LIGNE" | grep "path:" | cut -d ':' -f1)	# Garde uniquement le nom de la clé.
		fi
		if echo "$LIGNE" | grep -q "user:\|admin:"; then
			MANIFEST_USER=$(echo "$LIGNE" | grep "user:\|admin:" | cut -d ':' -f1)	# Garde uniquement le nom de la clé.
		fi
		MANIFEST_ARGS="$MANIFEST_ARGS$(echo "$LIGNE" | cut -d ':' -f1,2 | sed s/:/=/)&"	# Ajoute l'argument du manifest
	done < "$script_dir/manifest_extract"
	if [ "$MANIFEST_DOMAIN" == "null" ]
	then
		ECHO_FORMAT "La clé de manifest du domaine n'a pas été trouvée.\n" "lyellow"
		setup_sub_dir=0
		setup_root=0
		multi_instance=0
		wrong_user=0
		incorrect_path=0
		all_test=$((all_test-5))
	fi
	if [ "$MANIFEST_PATH" == "null" ]
	then
		ECHO_FORMAT "La clé de manifest du path n'a pas été trouvée.\n" "lyellow"
		setup_root=0
		multi_instance=0
		incorrect_path=0
		all_test=$((all_test-3))
	fi
	if [ "$MANIFEST_USER" == "null" ]
	then
		ECHO_FORMAT "La clé de manifest de l'user admin n'a pas été trouvée.\n" "lyellow"
		wrong_user=0
		all_test=$((all_test-1))
	fi
fi

TESTING_PROCESS
if [ "$no_lxc" -eq 0 ]; then
	LXC_TURNOFF
fi
TEST_RESULTS

echo "Le log complet des installations et suppressions est disponible dans le fichier $COMPLETE_LOG"
# Clean
rm -f "$OUTPUTD" "$temp_RESULT" "$script_dir/url_output" "$script_dir/curl_print" "$script_dir/manifest_extract"

sudo rm -rf "$APP_CHECK"
