
from flask import Flask, jsonify, request
import os
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Sample calendar events
EVENTS = [
    {
        "id": 1,
        "title": "Team Meeting",
        "start": "2024-08-22T09:00:00Z",
        "end": "2024-08-22T10:00:00Z",
        "attendees": ["john.doe@company.com", "jane.smith@company.com"]
    },
    {
        "id": 2,
        "title": "Project Review",
        "start": "2024-08-22T14:00:00Z",
        "end": "2024-08-22T15:30:00Z",
        "attendees": ["alice.brown@company.com", "bob.johnson@company.com"]
    },
    {
        "id": 3,
        "title": "Client Presentation",
        "start": "2024-08-23T11:00:00Z",
        "end": "2024-08-23T12:00:00Z",
        "attendees": ["john.doe@company.com", "alice.brown@company.com"]
    }
]

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'calendar-service',
        'version': os.getenv('VERSION', '1.0.0'),
        'timestamp': datetime.utcnow().isoformat(),
        'port': os.getenv('SERVICE_PORT', '5002')
    })

@app.route('/')
def home():
    return jsonify({
        'message': 'Calendar Service API',
        'version': os.getenv('VERSION', '1.0.0'),
        'service': os.getenv('SERVICE_NAME', 'calendar-service'),
        'endpoints': [
            'GET /health - Health check',
            'GET /events - List all events',
            'GET /events/<id> - Get event by ID',
            'POST /events - Create new event',
            'GET /events/today - Get today\'s events'
        ]
    })

@app.route('/events', methods=['GET'])
def get_events():
    return jsonify({
        'events': EVENTS,
        'count': len(EVENTS)
    })

@app.route('/events/<int:event_id>', methods=['GET'])
def get_event(event_id):
    event = next((e for e in EVENTS if e['id'] == event_id), None)
    if event:
        return jsonify(event)
    return jsonify({'error': 'Event not found'}), 404

@app.route('/events/today', methods=['GET'])
def get_today_events():
    today = datetime.now().date()
    today_events = []
    
    for event in EVENTS:
        event_date = datetime.fromisoformat(event['start'].replace('Z', '+00:00')).date()
        if event_date == today:
            today_events.append(event)
    
    return jsonify({
        'events': today_events,
        'date': today.isoformat(),
        'count': len(today_events)
    })

@app.route('/events', methods=['POST'])
def create_event():
    data = request.get_json()
    if not data or 'title' not in data or 'start' not in data:
        return jsonify({'error': 'Title and start time are required'}), 400
    
    new_event = {
        'id': max([e['id'] for e in EVENTS]) + 1,
        'title': data['title'],
        'start': data['start'],
        'end': data.get('end', data['start']),
        'attendees': data.get('attendees', [])
    }
    EVENTS.append(new_event)
    return jsonify(new_event), 201

if __name__ == '__main__':
    port = int(os.getenv('SERVICE_PORT', 5002))
    logger.info(f"Starting Calendar Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False) 
