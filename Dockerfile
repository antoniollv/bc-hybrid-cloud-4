FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /app
ARG VERSION=3.3.0-SNAPSHOT.jar
COPY target/spring-petclinic-$VERSION app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
EXPOSE 8080
