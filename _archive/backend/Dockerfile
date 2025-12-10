FROM node:18-alpine

# Imposta la directory di lavoro
WORKDIR /app

# Copia i file package
COPY package*.json ./

# Installa solo le dipendenze di produzione
RUN npm ci --only=production

# Copia il codice sorgente
COPY . .

# Esponi la porta (Cloud Run usa PORT env variable)
ENV PORT=8080
EXPOSE 8080

# Comando per avviare l'applicazione
CMD ["node", "server.js"]
