# Use a lightweight base image
FROM alpine:latest

# Install necessary tools
RUN apk add --no-cache bash curl grep gawk sed coreutils bc

# Set working directory
WORKDIR /app

# Copy scripts into the container
COPY spn.sh /app/

# Make the scripts executable
RUN chmod +x spn.sh

# Define the entrypoint for the container
ENTRYPOINT ["/app/spn.sh"]
