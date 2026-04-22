FROM debian:bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    sudo \
    jq \
    vim-common \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Add a non-root user for BrowserBox
RUN useradd -m -s /bin/bash browserbox && \
    echo "browserbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER browserbox
WORKDIR /home/browserbox

# Install BrowserBox using full-install
# BBX_TEST_AGREEMENT=true skips prompts
# BBX_FULL_INSTALL=true triggers full-install
# BBX_INSTALL_HOSTNAME="localhost"
# BBX_INSTALL_EMAIL="actions@browserbox.io"
# INSTALL_DOC_VIEWER="false" skips doc viewer
RUN curl -fsSL https://browserbox.io/install.sh | \
    BBX_TEST_AGREEMENT="true" \
    BBX_FULL_INSTALL="true" \
    BBX_INSTALL_HOSTNAME="localhost" \
    BBX_INSTALL_EMAIL="actions@browserbox.io" \
    INSTALL_DOC_VIEWER="false" \
    bash

# Ensure bbx is in PATH
ENV PATH="/home/browserbox/.local/bin:${PATH}"

# Expose the default BrowserBox port
EXPOSE 8080

# Default command
CMD ["bbx", "status"]
