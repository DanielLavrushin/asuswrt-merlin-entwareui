#!/bin/sh

export PATH=/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin
source /usr/sbin/helper.sh
DESC="Entware UI"
LOCKFILE=/tmp/addonentwareui.lock

DIR_WEB_ENTWAREUI="/www/user/entwareui"
DIR_SHARE_ENTWAREUI="/opt/share/entwareui"

UI_RESPONSE_FILE="/tmp/entwareui_response.json"

ENTWAREUI_VERSION="0.0"
ENTWAREUI_LOCKFILE="/tmp/entwareui.lock"

# Color Codes
CERR='\033[0;31m'
CSUC='\033[0;32m'
CWARN='\033[0;33m'
CINFO='\033[0;36m'
CRESET='\033[0m'

#error_handler() {}
#trap 'error_handler' EXIT

printlog() {
    if [ "$1" = "true" ]; then
        logger -t "ENTWAREUI" "$2"
    fi
    printf "${CINFO}${3}%s${CRESET}\\n" "$2"
}

get_webui_page() {
    USER_PAGE="none"
    max_user_page=0
    used_pages=""

    for page in /www/user/user*.asp; do
        if [ -f "$page" ]; then
            if grep -q "page:entwareui" "$page"; then
                USER_PAGE=$(basename "$page")
                printlog true "Found existing ENTWAREUI page: $USER_PAGE" $CSUC
                return
            fi

            user_number=$(echo "$page" | sed -E 's/.*user([0-9]+)\.asp$/\1/')
            used_pages="$used_pages $user_number"

            if [ "$user_number" -gt "$max_user_page" ]; then
                max_user_page="$user_number"
            fi
        fi
    done

    if [ "$USER_PAGE" != "none" ]; then
        printlog true "Found existing ENTWAREUI page: $USER_PAGE" $CSUC
        return
    fi

    if [ "$1" = "true" ]; then
        i=1
        while true; do
            if ! echo "$used_pages" | grep -qw "$i"; then
                USER_PAGE="user$i.asp"
                printlog true "Assigning new ENTWAREUI page: $USER_PAGE" $CSUC
                return
            fi
            i=$((i + 1))
        done
    fi
}

mount_ui() {

    FD=386
    eval exec "$FD>$LOCKFILE"
    flock -x "$FD"

    nvram get rc_support | grep -q am_addons
    if [ $? != 0 ]; then
        printlog true "This firmware does not support addons!" $CERR
        exit 5
    fi

    get_webui_page true

    if [ "$USER_PAGE" = "none" ]; then
        printlog true "Unable to install ENTWAREUI" $CERR
        exit 5
    fi

    printlog true "Mounting ENTWAREUI as $USER_PAGE"

    if [ ! -d $DIR_WEB_ENTWAREUI ]; then
        mkdir -p "$DIR_WEB_ENTWAREUI"
    fi

    if [ ! -d "$DIR_SHARE_ENTWAREUI/data" ]; then
        mkdir -p "$DIR_SHARE_ENTWAREUI/data"
    fi

    ln -s -f /jffs/addons/entwareui/index.asp /www/user/$USER_PAGE
    ln -s -f /jffs/addons/entwareui/app.js $DIR_WEB_ENTWAREUI/app.js
    ln -s -f $UI_RESPONSE_FILE $DIR_WEB_ENTWAREUI/response.json

    echo "ENTWAREUI" >"/www/user/$(echo $USER_PAGE | cut -f1 -d'.').title"

    if [ ! -f /tmp/menuTree.js ]; then
        cp /www/require/modules/menuTree.js /tmp/
        mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
    fi

    sed -i '/index: "menu_Setting"/,/index:/ {
  /url:\s*"NULL",\s*tabName:\s*"__INHERIT__"/ i \
    { url: "'"$USER_PAGE"'", tabName: "Entware" },
}' /tmp/menuTree.js

    umount /www/require/modules/menuTree.js && mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js

    flock -u "$FD"
    printlog true "ENTWAREUI mounted successfully as $USER_PAGE" $CSUC
}

unmount_ui() {
    FD=386
    eval exec "$FD>$LOCKFILE"
    flock -x "$FD"

    nvram get rc_support | grep -q am_addons
    if [ $? != 0 ]; then
        printlog true "This firmware does not support addons!" $CERR
        exit 5
    fi

    get_webui_page

    base_user_page="${USER_PAGE%.asp}"

    if [ -z "$USER_PAGE" ] || [ "$USER_PAGE" = "none" ]; then
        printlog true "No ENTWAREUI page found to unmount. Continuing to clean up..." $CWARN
    else
        printlog true "Unmounting ENTWAREUI $USER_PAGE"
        rm -fr /www/user/$USER_PAGE
        rm -fr /www/user/$base_user_page.title
    fi

    if [ ! -f /tmp/menuTree.js ]; then
        printlog true "menuTree.js not found, skipping unmount." $CWARN
    else
        printlog true "Removing any X-RAY menu entry from menuTree.js."
        # Safely remove entries with tabName: "X-RAY"
        grep -v "tabName: \"Entware\"" /tmp/menuTree.js >/tmp/menuTree_temp.js
        mv /tmp/menuTree_temp.js /tmp/menuTree.js

        umount /www/require/modules/menuTree.js
        mount -o bind /tmp/menuTree.js /www/require/modules/menuTree.js
    fi

    rm -rf $DIR_WEB_ENTWAREUI

    flock -u "$FD"

    printlog true "Unmount completed." $CSUC
}

remount_ui() {
    if [ "$1" != "skipwait" ]; then
        printlog true "sleeping for 10 seconds..." $CWARN
        # sleep 10
    fi

    unmount_ui
    mount_ui
}

am_settings_del() {
    local key="$1"
    sed -i "/$key/d" /jffs/addons/custom_settings.txt
}

reconstruct_payload() {
    FD=386
    eval exec "$FD>$ENTWAREUI_LOCKFILE"

    if ! flock -x "$FD"; then
        return 1
    fi

    local idx=0
    local chunk
    local payload=""
    while :; do
        chunk=$(am_settings_get eui_payload$idx)
        if [ -z "$chunk" ]; then
            break
        fi
        payload="$payload$chunk"
        idx=$((idx + 1))
    done

    cleanup_payloads

    echo "$payload"

    # Release the lock
    flock -u "$FD"
}

cleanup_payloads() {
    # clean up all payload chunks from the custom settings
    sed -i '/^eui_payload/d' /jffs/addons/custom_settings.txt
}

ensure_ui_response_file() {
    if [ ! -f "$UI_RESPONSE_FILE" ]; then
        printlog true "Creating Entware UI response file: $UI_RESPONSE_FILE"
        echo '{"entware":{}}' >"$UI_RESPONSE_FILE"
        chmod 600 "$UI_RESPONSE_FILE"
    fi

    if [ -f "$UI_RESPONSE_FILE" ]; then
        UI_RESPONSE=$(cat "$UI_RESPONSE_FILE")
    else
        UI_RESPONSE="{}"
    fi

}

update_loading_progress() {
    local message=$1
    local progress=$2

    ensure_ui_response_file

    if [ -n "$progress" ]; then

        UI_RESPONSE=$(echo "$UI_RESPONSE" | jq --argjson progress "$progress" --arg message "$message" '
            .loading.message = $message |
            .loading.progress = $progress
        ')
    else
        UI_RESPONSE=$(echo "$UI_RESPONSE" | jq --arg message "$message" '
            .loading.message = $message
        ')
    fi

    echo "$UI_RESPONSE" >"$UI_RESPONSE_FILE"

    if [ "$progress" = "100" ]; then
        /jffs/scripts/entwareui service_event cleanloadingprogress &
    fi

}

remove_loading_progress() {
    printlog true "Removing loading progress..."
    sleep 1
    ensure_ui_response_file

    UI_RESPONSE=$(echo "$UI_RESPONSE" | jq '
            del(.loading)
        ')

    echo "$UI_RESPONSE" >"$UI_RESPONSE_FILE"
    exit 0
}

packages_installed() {
    update_loading_progress "Getting installed packages..." 0
    printlog true "Getting installed packages..."
    ensure_ui_response_file

    UI_RESPONSE=$(echo "$UI_RESPONSE" | jq '.entware.installed = []')

    while IFS= read -r line; do
        pkg=$(echo "$line" | awk -F" - " '{print $1}')
        version=$(echo "$line" | awk -F" - " '{print $2}')
        UI_RESPONSE=$(echo "$UI_RESPONSE" | jq --arg pkg "$pkg" --arg ver "$version" \
            '.entware.installed += [{ "name": $pkg, "version": $ver }]')
    done <<EOF
$(opkg list-installed)
EOF

    echo "$UI_RESPONSE" >"$UI_RESPONSE_FILE"

    update_loading_progress "Installed packages retrieved." 100
    printlog true "Installed packages retrieved." $CSUC
}

case "$1" in
mount_ui)
    mount_ui
    ;;
unmount_ui)
    unmount_ui
    ;;
remount_ui)
    remount_ui $2
    ;;
service_event)
    case "$2" in
    cleanloadingprogress)
        remove_loading_progress
        ;;
    packages)
        case "$3" in
        installed)
            packages_installed
            ;;
        esac
        ;;
    esac
    exit 0
    ;;
*)
    echo "Usage: $0 {install|uninstall|start|stop|restart|update|mount_ui|unmount_ui|remount_ui}"
    exit 1
    ;;
esac

exit 0
