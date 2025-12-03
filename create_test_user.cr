require "./src/config"

# Simple script to create a test user with password
# Usage: crystal run create_test_user.cr

puts "Creating test user..."

user = App::Models::User.new(
  name: "Test User",
  email: "test@example.com"
)
user.password = "password123"

if user.save
  puts "✓ User created successfully!"
  puts "  Email: #{user.email}"
  puts "  Name: #{user.name}"
  puts "  ID: #{user.id}"
  puts "\nYou can now login at http://localhost:3000/auth/login"
  puts "  Email: test@example.com"
  puts "  Password: password123"
else
  puts "✗ Failed to create user"
  puts user.errors.inspect
end
