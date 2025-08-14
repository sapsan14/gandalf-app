# Stage 1 — Build the application
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

# Install Maven in the build container
# NB! Using system Maven for fewer hidden files, and it will work even if .mvn was never committed
RUN apt-get update && apt-get install -y maven && rm -rf /var/lib/apt/lists/*

# Copy pom.xml first to cache dependencies
COPY pom.xml ./

# Pre-download dependencies
RUN mvn dependency:go-offline

# Copy the full source code
COPY src src

# Build the JAR (skip tests for faster build)
RUN mvn clean package -DskipTests

# Stage 2 — Minimal runtime image
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# Copy the JAR from the build stage
COPY --from=build /app/target/*.jar app.jar

# Expose port 80 for the application
EXPOSE 80

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]