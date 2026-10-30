# Obraz „z szablonu firmowego”: slim, bez zależności, użytkownik bez roota.
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY *.py ./
COPY static/ static/
USER 10001
ENV PYTHONUNBUFFERED=1 PORT=8080
EXPOSE 8080
CMD ["python", "main.py"]
