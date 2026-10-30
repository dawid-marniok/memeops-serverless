FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY *.py ./
USER 10001
ENV PYTHONUNBUFFERED=1 PORT=8080
CMD ["python", "main.py"]
