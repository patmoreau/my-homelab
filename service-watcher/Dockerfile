FROM node:24-alpine

# Install OpenSSH client for QNAP connectivity
RUN apk add --no-cache openssh-client

WORKDIR /app

COPY package.json ./
RUN npm install

COPY . .

CMD ["npm", "start"]
