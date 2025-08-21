
from flask import Flask, jsonify, request
import os
import logging
import sys
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Sample data
USERS = [
    {"id": 1, "name": "John Doe", "email": "john.doe@company.com", "role": "admin"},
    {"id": 2, "name": "Jane Smith", "email": "jane.smith@company.com", "role": "user"},
    {"id": 3, "name": "Bob Johnson", "email": "bob.johnson@company.com", "role": "user"},
    {"id": 4, "name": "Alice Brown", "email": "alice.brown@company.com", "role": "manager"}
]

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'user-service',
        'version': os.getenv('VERSION', '1.0.0'),
        'timestamp': datetime.utcnow().isoformat(),
        'port': os.getenv('SERVICE_PORT', '5001')
    })

@app.route('/')
def home():
    return jsonify({
        'message': 'User Service API',
        'version': os.getenv('VERSION', '1.0.0'),
        'service': os.getenv('SERVICE_NAME', 'user-service'),
        'endpoints': [
            'GET /health - Health check',
            'GET /users - List all users',
            'GET /users/<id> - Get user by ID',
            'POST /users - Create new user'
        ]
    })

@app.route('/users', methods=['GET'])
def get_users():
    return jsonify({
        'users': USERS,
        'count': len(USERS)
    })

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    user = next((u for u in USERS if u['id'] == user_id), None)
    if user:
        return jsonify(user)
    return jsonify({'error': 'User not found'}), 404

@app.route('/users', methods=['POST'])
def create_user():
    data = request.get_json()
    if not data or 'name' not in data:
        return jsonify({'error': 'Name is required'}), 400
    
    new_user = {
        'id': max([u['id'] for u in USERS]) + 1,
        'name': data['name'],
        'email': data.get('email', ''),
        'role': data.get('role', 'user')
    }
    USERS.append(new_user)
    return jsonify(new_user), 201

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.getenv('SERVICE_PORT', 5001))
    logger.info(f"Starting User Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
