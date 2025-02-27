# Microservices System (HTTP Version)

Two Ruby on Rails services communicating via HTTP:
- **Users Service** (Port 3000) - Manages user data
- **Products Service** (Port 3001) - Manages product data

## Prerequisites

- Ruby 3.4+
- Rails 8.0+
- Bundler 2.6+
- SQLite3
- curl (for testing)

## Installation

```bash
# Clone repository
git clone git@github.com:doston9471/microservices-ruby.git
cd microservices-ruby

# Install dependencies for both services
cd service1 && bundle install && cd ..
cd service2 && bundle install && cd ..
```

## Run services

```bash
# Start Users Service (port 3000)
cd service1
rails db:create && rails db:migrate
rails s -p 3000

# Start Products Service (port 3001)
cd ../service2
rails db:create && rails db:migrate
rails s -p 3001
```

## Test API Endpoints

Users Service (http://localhost:3000)

```bash
# Create user
curl -X POST -H "Content-Type: application/json" \
  -d '{"user":{"name":"John","email":"john@example.com"}}' \
  http://localhost:3000/api/v1/users

# List users
curl http://localhost:3000/api/v1/users
```
Products Service (http://localhost:3001)

```bash
# Create product
curl -X POST -H "Content-Type: application/json" \
  -d '{"product":{"name":"Book","price":"19.99"}}' \
  http://localhost:3001/api/v1/products

# List products
curl http://localhost:3001/api/v1/products
```

Cross-Service Call

```bash
# Get products through Users Service
curl http://localhost:3000/api/v1/products
```

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/doston9471/microservices-ruby/blob/main/LICENSE) file for details.

## Version History

**1.0.0** - Initial release with HTTP-based communication
