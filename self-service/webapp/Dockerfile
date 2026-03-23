FROM ubuntu/python:3.12-24.04_stable

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app.py .
COPY templates/ templates/

# Create shared requests directory for volume mount
RUN mkdir -p /shared/requests && chmod 755 /shared/requests

# Run the app as a non-root user.
RUN useradd --create-home --shell /usr/sbin/nologin appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:5000/health || exit 1

# Expose port
EXPOSE 5000

# Run the Flask app
CMD ["python3", "app.py"]
