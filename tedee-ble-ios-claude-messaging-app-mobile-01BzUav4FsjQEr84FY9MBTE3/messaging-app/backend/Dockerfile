FROM node:18-alpine

# Installa dipendenze native necessarie per bcryptjs
RUN apk add --no-cache python3 make g++

# Imposta la directory di lavoro
WORKDIR /app

# Copia i file package
COPY package*.json ./

# Installa solo le dipendenze di produzione
RUN npm ci --omit=dev

# Copia il codice sorgente
COPY . .

# Esponi la porta (Cloud Run usa PORT env variable)
ENV PORT=8080
EXPOSE 8080

# Comando per avviare l'applicazione
CMD ["node", "server.js"]
