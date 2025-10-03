# Build stage
FROM node:20-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY tsconfig.json tsconfig.node.json vite.config.ts index.html ./
COPY src ./src
ARG VITE_BACKEND_URL=http://localhost:8080
ARG VITE_COGNITO_REGION
ARG VITE_COGNITO_USER_POOL_ID
ARG VITE_COGNITO_APP_CLIENT_ID
ARG VITE_DEBUG_PLAYER_ID

ENV VITE_BACKEND_URL=${VITE_BACKEND_URL} \
	VITE_COGNITO_REGION=${VITE_COGNITO_REGION} \
	VITE_COGNITO_USER_POOL_ID=${VITE_COGNITO_USER_POOL_ID} \
	VITE_COGNITO_APP_CLIENT_ID=${VITE_COGNITO_APP_CLIENT_ID} \
	VITE_DEBUG_PLAYER_ID=${VITE_DEBUG_PLAYER_ID}

RUN npm run build

# Runtime stage
FROM nginx:1.27-alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
