FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /app
ARG JAR_FILE=spring-petclinic-3.3.0-SNAPSHOT.jar
COPY target/${JAR_FILE} app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EXPOSE 8080
