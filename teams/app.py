from flask import Flask, jsonify, request
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Sample teams and messages data
TEAMS = [
    {
        "id": 1,
        "name": "Development Team",
        "members": ["john.doe@company.com", "jane.smith@company.com", "bob.johnson@company.com"],
        "created": "2024-01-15T10:00:00Z"
    },
    {
        "id": 2,
        "name": "Marketing Team",
        "members": ["alice.brown@company.com", "jane.smith@company.com"],
        "created": "2024-02-01T14:30:00Z"
    }
]

MESSAGES = [
    {
        "id": 1,
        "team_id": 1,
        "from": "john.doe@company.com",
        "message": "Good morning everyone! Ready for today's sprint review?",
        "timestamp": "2024-08-21T08:30:00Z",
        "type": "text"
    },
    {
        "id": 2,
        "team_id": 1,
        "from": "jane.smith@company.com",
        "message": "Yes! I've prepared the demo for the new features.",
        "timestamp": "2024-08-21T08:32:00Z",
        "type": "text"
    },
    {
        "id": 3,
        "team_id": 2,
        "from": "alice.brown@company.com",
        "message": "The new campaign metrics look promising!",
        "timestamp": "2024-08-21T10:15:00Z",
        "type": "text"
    }
]

MEETINGS = [
    {
        "id": 1,
        "team_id": 1,
        "title": "Daily Standup",
        "start": "2024-08-22T09:00:00Z",
        "duration": 30,
        "participants": ["john.doe@company.com", "jane.smith@company.com"]
    }
]

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'teams-service',
        'version': os.getenv('VERSION', '1.0.0'),
        'timestamp': datetime.utcnow().isoformat(),
        'port': os.getenv('SERVICE_PORT', '5005')
    })

@app.route('/')
def home():
    return jsonify({
        'message': 'Teams Service API',
        'version': os.getenv('VERSION', '1.0.0'),
        'service': os.getenv('SERVICE_NAME', 'teams-service'),
        'endpoints': [
            'GET /health - Health check',
            'GET /teams - List all teams',
            'GET /teams/<id> - Get team by ID',
            'GET /teams/<id>/messages - Get team messages',
            'GET /meetings - List all meetings',
            'POST /teams/<id>/messages - Send message to team'
        ]
    })

@app.route('/teams', methods=['GET'])
def get_teams():
    return jsonify({
        'teams': TEAMS,
        'count': len(TEAMS)
    })

@app.route('/teams/<int:team_id>', methods=['GET'])
def get_team(team_id):
    team = next((t for t in TEAMS if t['id'] == team_id), None)
    if team:
        return jsonify(team)
    return jsonify({'error': 'Team not found'}), 404

@app.route('/teams/<int:team_id>/messages', methods=['GET'])
def get_team_messages(team_id):
    team_messages = [m for m in MESSAGES if m['team_id'] == team_id]
    return jsonify({
        'messages': team_messages,
        'count': len(team_messages),
        'team_id': team_id
    })

@app.route('/teams/<int:team_id>/messages', methods=['POST'])
def send_team_message(team_id):
    data = request.get_json()
    if not data or 'message' not in data:
        return jsonify({'error': 'Message content is required'}), 400
    
    # Check if team exists
    team = next((t for t in TEAMS if t['id'] == team_id), None)
    if not team:
        return jsonify({'error': 'Team not found'}), 404
    
    new_message = {
        'id': max([m['id'] for m in MESSAGES]) + 1,
        'team_id': team_id,
        'from': data.get('from', 'user@company.com'),
        'message': data['message'],
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'type': 'text'
    }
    MESSAGES.append(new_message)
    
    return jsonify(new_message), 201

@app.route('/meetings', methods=['GET'])
def get_meetings():
    return jsonify({
        'meetings': MEETINGS,
        'count': len(MEETINGS)
    })

@app.route('/stats', methods=['GET'])
def get_stats():
    total_teams = len(TEAMS)
    total_messages = len(MESSAGES)
    total_meetings = len(MEETINGS)
    
    # Calculate members across all teams (with potential duplicates)
    all_members = []
    for team in TEAMS:
        all_members.extend(team['members'])
    unique_members = len(set(all_members))
    
    return jsonify({
        'total_teams': total_teams,
        'total_messages': total_messages,
        'total_meetings': total_meetings,
        'unique_members': unique_members,
        'active_teams': total_teams  # All teams are considered active for this demo
    })

if __name__ == '__main__':
    port = int(os.getenv('SERVICE_PORT', 5005))
    logger.info(f"Starting Teams Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
