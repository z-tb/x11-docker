#!/bin/bash
set -e


# -----------------------------
# consistent output formatting
# -----------------------------
info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# -----------------------------
# helper functions: input sanitization
# Allow only digits for UID/GID
# -----------------------------
sanitize_numeric() {
    printf '%s' "$1" | tr -cd '0-9'
}

# Limit POSIX username/groupname characters (limited, sorry no dots. add them if you want)
sanitize_name() {
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9_-'
}

# Limit file-path characters (limited, sorry no dots. Add them if you want)
sanitize_path() {
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9_/\-'
}

# supplemental group arg - only allow a few sane characters
sanitize_supp_groups() {
    # allowed characters: groupnames [a-zA-Z0-9_-], GIDs [0-9], comma and colon
    printf '%s' "$1" | tr -cd 'a-zA-Z0-9_,:-'
}

info "Group list is: $USER_GROUPS"

# -----------------------------
# Sanitize any passed variables untime provisioning: user info for runtime user. These should match host system so UID and GID match when writes
# happen to the volume mounts
# -----------------------------
raw_USER_UID="$(sanitize_numeric "$USER_UID")"
raw_USER_GROUP_GID="$(sanitize_numeric "$USER_GROUP_GID")"
raw_USER_GROUP_NAME="$(sanitize_name "$USER_GROUP_NAME")"
raw_USER_NAME="$(sanitize_name "$USER_NAME")"
raw_USER_SHELL="$(sanitize_path "$USER_SHELL")"
raw_USER_HOME="$(sanitize_path "$USER_HOME")"
raw_USER_GROUPS="$(sanitize_supp_groups "$USER_GROUPS")"

# provision using sanitized values
USER_UID="${raw_USER_UID:-1000}"
USER_GROUP_GID="${raw_USER_GROUP_GID:-1000}"
USER_GROUP_NAME="${raw_USER_GROUP_NAME:-user}"
USER_NAME="${raw_USER_NAME:-user}"
USER_SHELL="${raw_USER_SHELL:-/bin/bash}"
USER_HOME="${raw_USER_HOME:-/home/$USER_NAME}"
USER_GROUPS="${raw_USER_GROUPS:-}"

# -----------------------------
# Ceate symlinks, report errors
# Add more symlinks below, if needed
# -----------------------------
symlink_status=0
create_symlink() {
    local src=$1
    local dest=$2
    local label=$3

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        warn "[SYMLINK] $label already exists: $dest"
    else
        if ln -s "$src" "$dest"; then
            success "[SYMLINK] $label created: $src → $dest"
        else
            warn "[SYMLINK] Failed to create $label: $src → $dest"
            symlink_status=1
        fi
    fi
}

# -----------------------------
# Runtime provisioning: startup
# -----------------------------
info "Starting /usr/local/bin/entrypoint.sh as UID $(id -u)..."

# if uid 1000, change to TARGET_UID TARGET_GID
if [ "$(id -u)" == "1000" ]; then
    # drop privs to user and start shell
    info "Starting as UID $(id -u)..."
    exec sudo -u ubuntu -H bash
    
fi

# if not started with root, then don't bother trying to create any accounts
if [ "$(id -u)" != "0" ]; then
    info "Not started as root:q, or UID 1000. exiting."
    exit
fi


# start as ubuntu user if minimum variables aren't available/provided
if [ -z "$USER_UID" ] || \
   [ -z "$USER_GROUP_GID" ] || \
   [ -z "$USER_GROUP_NAME" ] || \
   [ -z "$USER_NAME" ] || \
   [ -z "$USER_SHELL" ] || \
   [ -z "$USER_HOME" ]; then
    
    warn "Ensure USER_UID, USER_GID, USER_GROUP_NAME, USER_NAME, USER_SHELL, and USER_HOME are set."
    warn "Starting with default values..."

    # drop privs to ubuntu user and start shell
    exec sudo -u ubuntu -H bash
fi

# -----------------------------
# Create user primary group. probably shouldn't exist yet
# -----------------------------
info "Creating user group $USER_GROUP_NAME"
if ! getent group "$USER_GROUP_NAME" >/dev/null; then
    if sudo groupadd -g "$USER_GROUP_GID" "$USER_GROUP_NAME"; then
        success "[GROUP] Created group \e[1;34m$USER_GROUP_NAME\e[0m (GID $USER_GROUP_GID)"
    else
        warn "[GROUP] Failed to create group \e[1;33m$USER_GROUP_NAME\e[0m"
    fi
else
    warn "[GROUP] Group \e[1;33m$USER_GROUP_NAME\e[0m already exists"
fi

# -----------------------------
# Create user from runtime UID/GID
# -----------------------------
info "Creating user account for $USER_NAME"
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    # Only use -m if home directory does not already exist
    USERADD_ARGS=("-u" "$USER_UID" "-g" "$USER_GROUP_GID" "-G" "sudo" "-d" "$USER_HOME" "-s" "$USER_SHELL")
    [ ! -d "$USER_HOME" ] && USERADD_ARGS+=("-m")

    if sudo useradd "${USERADD_ARGS[@]}" "$USER_NAME"; then
        echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/sudo-users >/dev/null
        success "[USER] Created user \e[1;34m$USER_NAME\e[0m (UID $USER_UID)"
    else
        warn "[USER] Failed to create user \e[1;31m$USER_NAME\e[0m"
    fi
else
    warn "[USER] User \e[1;33m$USER_NAME\e[0m already exists"
fi


# -----------------------------
# Setup home directories
# -----------------------------
info "Creating home subdirectories in $USER_HOME"
if mkdir -p "$USER_HOME/.config" "$USER_HOME/.local"; then
    success "[HOME] Created home subdirectory \e[1;34m$USER_HOME\e[0m"
else
    warn "[HOME] Home subdirectories already exist"
fi

if chown -R "$USER_UID:$USER_GROUP_GID" "$USER_HOME"; then
    success "[HOME] Set ownership for \e[1;34m$USER_HOME\e[0m"
else
    warn "[HOME] Failed to set ownership for \e[1;31m$USER_HOME\e[0m"
fi

# -----------------------------
# Create supplemental groups from runtime arg - if not empty
# Format: "group1:gid1,group2:gid2"
# -----------------------------
if [ -n "$USER_GROUPS" ]; then
    info "Creating supplementary groups: $USER_GROUPS"
    count=0
    added=0

    IFS=',' read -ra group_entries <<< "$USER_GROUPS"
    for entry in "${group_entries[@]}"; do
        let count+=1
        # Split & sanitize - probably no need to do it on the split variables if done above
        group_name_raw=$(printf '%s' "$entry" | cut -d: -f1)
        group_gid_raw=$(printf '%s' "$entry" | cut -d: -f2)

        group_name=$(sanitize_name "$group_name_raw")
        group_gid=$(sanitize_numeric "$group_gid_raw")

        # Check for empty values
        if [ -z "$group_name" ] || [ -z "$group_gid" ]; then
            warn "[SUPP_GROUP] Skipping empty value #$count."
            continue
        fi

        # Create group if missing
        if ! getent group "$group_name" >/dev/null; then
            
            if groupadd -g "$group_gid" "$group_name"; then
                success "[SUPP_GROUP] Created group $group_name"
            else
                warn "[SUPP_GROUP] Failed to create group $group_name"
                continue
            fi
        else
            warn "[SUPP_GROUP] Group $group_name already exists"
        fi

        # Add user to this supplementary group
        if usermod -aG "$group_name" "$USER_NAME"; then
            let added+=1
        else
            warn "[SUPP_GROUP] Failed to add $USER_NAME to $group_name"
        fi
    done

    info "[SUPP_GROUP] add user to $added/$count supplementary groups"
else
    info "USER_GROUPS is empty—skipping supplementary group setup."
fi



# -----------------------------
# Append custom bashrc additions
# -----------------------------
info "Checking for bashrc additions in $USER_HOME/.bashrc"
if ! grep -q 'pcol' "$USER_HOME/.bashrc" 2>/dev/null; then
    if echo 'pcol' >> "$USER_HOME/.bashrc"; then
        success "[BASHRC] Appended custom bashrc additions to \e[1;34m$USER_HOME/.bashrc\e[0m"
    else
        warn "[BASHRC] Failed to append custom bashrc additions"
    fi
else
    warn "[BASHRC] Custom bashrc additions already present"
fi

# -----------------------------
# Mount-based symlinks for user config
# -----------------------------
info "Creating symlinks for mounted home directories..."

# SSH symlink only if SSH agent not detected
if [ -z "$SSH_AUTH_SOCK" ]; then
    create_symlink "/mnt/home/${USER_NAME}/.ssh" "$USER_HOME/.ssh" "SSH directory"
else
    success "[SSH] SSH agent detected; skipping SSH symlink"
fi

# Other configs
# create_symlink "/mnt/home/${USER_NAME}/.gitconfig"    "$USER_HOME/.gitconfig" "Git config"
#create_symlink "/mnt/home/${USER_NAME}/.kiro"         "$USER_HOME/.kiro" "Kiro settings"
#create_symlink "/mnt/home/${USER_NAME}/.config/Kiro"  "$USER_HOME/.config/Kiro" "Kiro config"
#create_symlink "/mnt/home/${USER_NAME}/.config/pulse" "$USER_HOME/.config/pulse" "PulseAudio config"

# -----------------------------
# Symlink summary
# -----------------------------
if [ $symlink_status -eq 0 ]; then
    success "[SYMLINK] All symlinks created successfully"
else
    warn "[SYMLINK] Some symlinks failed (see messages above)"
fi

# -----------------------------
# SSH agent / key - prefer forwarded agent if available
# -----------------------------
info "Checking for SSH agent..."
if [ -z "$SSH_AUTH_SOCK" ]; then
    warn "[SSH] SSH agent not detected (SSH_AUTH_SOCK empty)"
    echo "   ssh-agent forwarding will not be enabled inside the container."
    echo "   Options:"
    echo "     1) Forward your host SSH agent:"
    echo "        docker run -it -v \$SSH_AUTH_SOCK:\$SSH_AUTH_SOCK -e SSH_AUTH_SOCK=\$SSH_AUTH_SOCK ..."
    echo "     2) Symlink your host SSH keys:"
    echo "        ln -s /mnt/home/${USER_NAME}/.ssh \$HOME/.ssh"
else
    success "[SSH] SSH agent detected via SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
fi

# -----------------------------
# Completion
# -----------------------------

# drop privs to runtime user and start shell
success "Runtime user provisioning complete. Starting shell for \033[1;34m${USER_NAME}\033[0m..."

# info "Setting password for $USER_NAME. You will need this for sudo in the container."
# sudo passwd "$USER_NAME" || exit
# echo "$USER_NAME ALL=(ALL:ALL) ALL" | sudo tee /etc/sudoers.d/sudo-users >/dev/null
#exec sudo -u "$USER_NAME" -H bash
exec sudo --preserve-env=SSH_AUTH_SOCK,DISPLAY -u "$USER_NAME" -H bash
