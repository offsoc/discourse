#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Discourse Development Environment Setup Script ---
# This script automates the installation of Discourse for local development on Ubuntu/Debian.
# It assumes you are running it as a non-root user with sudo privileges.

echo "--- Starting Discourse Development Environment Setup Script ---"

# Check for root privileges - crucial for initial package installations
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script needs to be run with 'sudo'."
  echo "Usage: sudo ./setup_discourse_dev.sh"
  exit 1
fi

# Get the original user who invoked sudo for user-specific installations
# This is crucial for rbenv, RubyGems, and Discourse code to be in the correct user's home directory.
DISCOURSE_USER="${SUDO_USER}"
if [ -z "$DISCOURSE_USER" ]; then
  echo "Error: Could not determine the user who invoked sudo. Please ensure you are running this script with sudo."
  exit 1
fi

USER_HOME=$(eval echo "~$DISCOURSE_USER") # Get the home directory of the actual user
if [ ! -d "$USER_HOME" ]; then
  echo "Error: User '$DISCOURSE_USER' home directory '$USER_HOME' does not exist."
  exit 1
fi

echo "Setting up Discourse development environment for user: $DISCOURSE_USER"

# --- 1. Update System and Install Core Dependencies ---
echo "--- 1. Updating system and installing core dependencies ---"
apt update -y
apt upgrade -y
# The list below covers git, postgres client libs, imagemagick, sqlite, nodejs, npm, curl, build tools.
# MailHog and ImageMagick are explicitly mentioned as optional, so we'll include them.
# The previous prompt's list was for dnf, this is adapted for apt.
apt install -y \
    git \
    build-essential \
    zlib1g-dev \
    libssl-dev \
    libreadline-dev \
    libyaml-dev \
    libpq-dev \
    libsqlite3-dev \
    nodejs \
    npm \
    curl \
    bzip2 \
    imagemagick \
    libmagickwand-dev \
    mailhog \
    sqlite3 # ensure sqlite3 executable is present

# --- 2. Install rbenv, ruby-build, and Ruby ---
echo "--- 2. Installing rbenv, ruby-build, and Ruby (latest stable) ---"
# These commands must be run as the target user ($DISCOURSE_USER)
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "Switching to user '$DISCOURSE_USER' for rbenv and Ruby installation..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"

  # Clone rbenv
  if [ ! -d "$HOME/.rbenv" ]; then
    echo "Cloning rbenv repository..."
    git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
    cd "$HOME/.rbenv" && src/configure && make -C src
    # Add rbenv to bashrc for future sessions and source for current
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'eval "$(rbenv init - --no-rehash)"' >> "$HOME/.bashrc"
  else
    echo "rbenv already exists, skipping clone."
  fi

  # Source .bashrc or eval rbenv init to ensure rbenv commands are available in this subshell
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true

  # Clone ruby-build plugin
  if [ ! -d "$(rbenv root)/plugins/ruby-build" ]; then
    echo "Cloning ruby-build plugin..."
    git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build
  else
    echo "ruby-build already exists, skipping clone."
  fi

  echo "Verifying rbenv installation with rbenv-doctor..."
  # rbenv-doctor might try to print to stderr which can cause issues with 'set -e'
  # We'll run it and check its exit status explicitly.
  if ! curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-doctor | bash; then
    echo "Warning: rbenv-doctor reported issues. Please review its output."
  fi

  # Get the latest stable Ruby version
  LATEST_RUBY_VERSION=$(rbenv install -l | grep -v - | tail -1)
  echo "Installing Ruby $LATEST_RUBY_VERSION (latest stable)..."
  rbenv install "$LATEST_RUBY_VERSION" || echo "Ruby $LATEST_RUBY_VERSION might already be installed, continuing..."
  rbenv global "$LATEST_RUBY_VERSION"
  rbenv rehash
  echo "Current Ruby version: $(ruby -v)"

  echo "Installing bundler gem..."
  gem install bundler
  echo "Updating system gems..."
  gem update --system
EOF

# --- 3. Install npm global packages (pnpm) ---
echo "--- 3. Installing npm global packages (pnpm) ---"
# npm is installed as root, so this should be fine directly
npm install -g pnpm

# --- 4. Install and Setup PostgreSQL & Redis ---
echo "--- 4. Installing and setting up PostgreSQL & Redis ---"
apt install -y postgresql redis-server

echo "Enabling and starting PostgreSQL service..."
systemctl enable postgresql
systemctl start postgresql

echo "Enabling and starting Redis service..."
systemctl enable redis-server
systemctl start redis-server

# Create PostgreSQL role for the Discourse user
echo "Creating PostgreSQL role for user: $DISCOURSE_USER..."
# This command needs to run as the 'postgres' system user.
sudo -u postgres createuser -s "$DISCOURSE_USER"

# --- 5. Clone Discourse Code ---
echo "--- 5. Cloning Discourse code to $USER_HOME/discourse ---"
DISCOURSE_APP_DIR="$USER_HOME/discourse"

sudo -u "$DISCOURSE_USER" bash << EOF
  echo "Switching to user '$DISCOURSE_USER' for cloning Discourse..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true

  if [ ! -d "$DISCOURSE_APP_DIR/.git" ]; then
    echo "Cloning Discourse repository..."
    git clone https://github.com/discourse/discourse.git "$DISCOURSE_APP_DIR"
  else
    echo "Discourse repository already exists at '$DISCOURSE_APP_DIR', skipping clone."
  fi
  cd "$DISCOURSE_APP_DIR"
EOF

# --- 6. Bootstrap Discourse (Install Gems and JS dependencies) ---
echo "--- 6. Bootstrapping Discourse (installing gems and JS dependencies) ---"
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "Switching to Discourse directory: $DISCOURSE_APP_DIR and installing dependencies..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true
  cd "$DISCOURSE_APP_DIR"

  echo "Installing Ruby gems with bundle install..."
  bundle install --jobs=$(nproc) # Use all available CPU cores for faster installation

  echo "Installing JavaScript dependencies with pnpm install..."
  pnpm install
EOF

# --- 7. Setup Database ---
echo "--- 7. Setting up Discourse databases ---"
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "Switching to Discourse directory and running database migrations..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true
  cd "$DISCOURSE_APP_DIR"

  echo "Creating and migrating development database..."
  bin/rails db:create
  bin/rails db:migrate

  echo "Creating and migrating test database..."
  RAILS_ENV=test bin/rails db:create db:migrate
EOF

# --- Final Instructions ---
echo "--- Discourse Development Setup Complete! ---"
echo ""
echo "To **start your Discourse server** for development, you need to:"
echo "1. Switch to your user:      su - $DISCOURSE_USER"
echo "2. Navigate to Discourse:    cd $DISCOURSE_APP_DIR"
echo "3. Start MailHog:            mailhog (in a separate terminal or background)"
echo "4. Start Ember server:       bin/ember-cli -u"
echo ""
echo "You should now be able to navigate to http://localhost:4200 to see your local Discourse installation."
echo ""
echo "To **create a new admin account**, run this command in your Discourse directory (after starting the server):"
echo "  bin/rails admin:create"
echo "Follow the prompts."
echo ""
echo "Happy hacking! For more development insights, check out the Beginner’s Guide to Creating Discourse Plugins."
echo ""
echo "Remember: This is a development setup. For production, use the official Docker installer."
