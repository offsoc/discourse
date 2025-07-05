#!/bin/bash
set -e # 任何命令失败时立即退出脚本

# --- 警告：生产环境安装注意事项 ---
# 本脚本将自动化您提供的 Discourse 手动安装步骤。
# 请注意，这些步骤通常用于开发或测试环境。
# 对于生产环境，Discourse 官方强烈建议使用其 Docker 安装器，以获得更稳定、安全和易于维护的部署。
# 官方 Docker 安装指南：https://github.com/discourse/discourse_docker
# --- 警告结束 ---

echo "--- 开始 Discourse 自动化安装脚本 ---"
echo "此脚本将安装 Discourse 及其依赖项。请确保您有稳定的网络连接。"

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 'sudo ./install_discourse.sh' 运行此脚本。"
  exit 1
fi

# 获取当前执行 sudo 命令的用户名，用于后续非 root 用户的操作
DISCOURSE_USER="${SUDO_USER}"
if [ -z "$DISCOURSE_USER" ]; then
  echo "错误：无法确定当前 sudo 用户。请确保您通过 sudo 运行此脚本。"
  exit 1
fi

echo "将为用户 '$DISCOURSE_USER' 安装 Discourse。"
echo "请确保 '$DISCOURSE_USER' 是一个存在的普通用户。"

# --- 1. 更新系统并安装系统和开发软件包 ---
echo "--- 1. 更新系统并安装系统和开发软件包 ---"
dnf update -y
dnf install -y "@development-tools" git rpm-build zlib-devel ruby-devel readline-devel libpq-devel ImageMagick sqlite sqlite-devel nodejs npm curl gcc g++ bzip2 openssl-devel libyaml-devel libffi-devel gdbm-devel ncurses-devel optipng pngquant jhead jpegoptim gifsicle oxipng

# --- 2. 安装所需的 npm 软件包 ---
echo "--- 2. 安装所需的 npm 软件包 (svgo, pnpm) ---"
npm install -g svgo pnpm

# --- 3. 安装和设置 PostgreSQL ---
echo "--- 3. 安装和设置 PostgreSQL ---"
dnf install -y postgresql-server postgresql-contrib
postgresql-setup --initdb --unit postgresql # 初始化数据库
systemctl enable postgresql # 设置开机自启动
systemctl start postgresql # 启动 PostgreSQL 服务

# 创建 PostgreSQL 用户。注意：这里将当前 sudo 用户设置为 PostgreSQL 的超级用户。
# 生产环境中，建议为 Discourse 创建一个专用的、权限受限的数据库用户。
echo "创建 PostgreSQL 用户：'$DISCOURSE_USER' 作为超级用户..."
sudo -u postgres createuser -s "$DISCOURSE_USER"

# --- 4. 安装和设置 Redis ---
echo "--- 4. 安装和设置 Redis ---"
dnf install -y redis
systemctl enable redis # 设置开机自启动
systemctl start redis # 启动 Redis 服务

# --- 5. 安装 rbenv、ruby-build 和 Ruby ---
echo "--- 5. 安装 rbenv、ruby-build 和 Ruby 2.7.1 ---"
# rbenv 和 Ruby 应该安装在普通用户的家目录下，而不是 root 用户下。
# 这里通过 'sudo -u' 切换到目标用户执行。

# 确保目标用户的家目录存在
USER_HOME=$(eval echo "~$DISCOURSE_USER")
if [ ! -d "$USER_HOME" ]; then
  echo "错误：用户 '$DISCOURSE_USER' 的家目录 '$USER_HOME' 不存在。"
  exit 1
fi

sudo -u "$DISCOURSE_USER" bash << EOF
  echo "进入用户 '$DISCOURSE_USER' 的环境..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"

  # 克隆 rbenv
  if [ ! -d "$HOME/.rbenv" ]; then
    echo "克隆 rbenv 仓库..."
    git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
    cd "$HOME/.rbenv" && src/configure && make -C src
    # 将 rbenv 初始化命令添加到 .bashrc，并为当前会话 source
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'eval "$(rbenv init - --no-rehash)"' >> "$HOME/.bashrc"
  else
    echo "rbenv 已存在，跳过克隆。"
  fi

  # 重新加载 bashrc 或直接 eval rbenv init 以确保 rbenv 命令可用
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true

  # 克隆 ruby-build 插件
  if [ ! -d "$(rbenv root)/plugins/ruby-build" ]; then
    echo "克隆 ruby-build 插件..."
    git clone https://github.com/rbenv/ruby-build.git "$(rbenv root)"/plugins/ruby-build
  else
    echo "ruby-build 已存在，跳过克隆。"
  fi

  echo "验证 rbenv 安装..."
  curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-doctor | bash

  echo "安装 Ruby 2.7.1..."
  rbenv install 2.7.1 || echo "Ruby 2.7.1 可能已安装，继续..."
  rbenv global 2.7.1
  rbenv rehash
  echo "当前 Ruby 版本：$(ruby -v)"
EOF

# --- 6. 安装 Ruby 依赖项 ---
echo "--- 6. 安装 Ruby 依赖项 (bundler, mailcatcher, rails) ---"
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "进入用户 '$DISCOURSE_USER' 的环境..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true

  echo "更新 gem 系统..."
  gem update --system
  echo "安装 bundler, mailcatcher, rails gem..."
  gem install bundler mailcatcher rails
EOF

# --- 7. 克隆 Discourse 代码 ---
echo "--- 7. 克隆 Discourse 代码 ---"
DISCOURSE_APP_DIR="$USER_HOME/discourse"

sudo -u "$DISCOURSE_USER" bash << EOF
  echo "进入用户 '$DISCOURSE_USER' 的环境..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true

  if [ ! -d "$DISCOURSE_APP_DIR/.git" ]; then
    echo "克隆 Discourse 仓库到 '$DISCOURSE_APP_DIR'..."
    git clone https://github.com/discourse/discourse.git "$DISCOURSE_APP_DIR"
  else
    echo "Discourse 仓库已存在于 '$DISCOURSE_APP_DIR'，跳过克隆。"
  fi
  cd "$DISCOURSE_APP_DIR"
EOF

# --- 8. 安装 Discourse 依赖项 ---
echo "--- 8. 安装 Discourse 依赖项 (bundle install, pnpm install) ---"
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "进入 Discourse 目录并安装依赖..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true
  cd "$DISCOURSE_APP_DIR"

  echo "运行 bundle install..."
  bundle install --jobs=$(nproc) # 使用多核加速安装
  echo "运行 pnpm install..."
  pnpm install
EOF

# --- 9. 创建所需的数据库并加载架构 ---
echo "--- 9. 创建所需的数据库并加载架构 ---"
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "进入 Discourse 目录并创建/迁移数据库..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true
  cd "$DISCOURSE_APP_DIR"

  # 注意：Discourse 默认会尝试连接到 postgres://localhost/discourse_development
  # 确保 PostgreSQL 已启动且用户 '$DISCOURSE_USER' 有权限。
  # 如果您遇到数据库连接问题，可能需要手动配置 config/database.yml 或设置 DATABASE_URL 环境变量。
  echo "创建和迁移开发数据库..."
  bundle exec rake db:create db:migrate

  echo "创建和迁移测试数据库..."
  RAILS_ENV=test bundle exec rake db:create db:migrate
EOF

# --- 10. 通过运行测试来测试安装 ---
echo "--- 10. 通过运行测试来测试安装 (bundle exec rake autospec) ---"
sudo -u "$DISCOURSE_USER" bash << EOF
  echo "进入 Discourse 目录并运行测试..."
  export HOME="$USER_HOME"
  export PATH="$HOME/.rbenv/bin:$PATH"
  source "$HOME/.bashrc" || eval "$(rbenv init - --no-rehash)" || true
  cd "$DISCOURSE_APP_DIR"

  bundle exec rake autospec
  echo "测试运行完毕。请检查输出以确认没有错误。"
EOF

echo "--- 11. 运行应用程序 ---"
echo "Discourse 已安装完成！"
echo ""
echo "要启动 Discourse 应用程序，请切换到用户 '$DISCOURSE_USER'，然后进入 Discourse 目录并运行以下命令："
echo ""
echo "  su - $DISCOURSE_USER"
echo "  cd $DISCOURSE_APP_DIR"
echo "  bundle exec rails server"
echo ""
echo "应用程序启动后，您应该能够在浏览器中访问 http://localhost:3000 来看到 Discourse 设置页面。"
echo ""
echo "--- 再次强调：生产环境安装注意事项 ---"
echo "本脚本是基于您提供的手动步骤自动化，更适合开发/测试环境。"
echo "对于生产环境，Discourse 官方强烈推荐使用其 Docker 安装器，因为它提供了更健壮、更易于维护和扩展的部署方案。"
echo "官方 Docker 安装指南：https://github.com/discourse/discourse_docker"
echo "--- 脚本执行完毕 ---"
