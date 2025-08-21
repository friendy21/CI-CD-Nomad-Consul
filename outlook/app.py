from flask import Flask, jsonify, request
import os
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Sample email data
EMAILS = [
    {
        "id": 1,
        "from": "client@example.com",
        "to": "john.doe@company.com",
        "subject": "Project Update Required",
        "body": "Please provide an update on the current project status.",
        "received": "2024-08-21T09:15:00Z",
        "read": False,
        "important": True
    },
    {
        "id": 2,
        "from": "hr@company.com",
        "to": "all@company.com",
        "subject": "Team Building Event Next Week",
        "body": "Don't forget about our team building event scheduled for next Friday.",
        "received": "2024-08-21T11:30:00Z",
        "read": True,
        "important": False
    },
    {
        "id": 3,
        "from": "vendor@supplier.com",
        "to": "alice.brown@company.com",
        "subject": "Invoice #12345",
        "body": "Please find attached invoice for your recent order.",
        "received": "2024-08-21T14:20:00Z",
        "read": False,
        "important": False
    }
]

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'outlook-service',
        'version': os.getenv('VERSION', '1.0.0'),
        'timestamp': datetime.utcnow().isoformat(),
        'port': os.getenv('SERVICE_PORT', '5004')
    })

@app.route('/')
def home():
    return jsonify({
        'message': 'Outlook Service API',
        'version': os.getenv('VERSION', '1.0.0'),
        'service': os.getenv('SERVICE_NAME', 'outlook-service'),
        'endpoints': [
            'GET /health - Health check',
            'GET /emails - List all emails',
            'GET /emails/<id> - Get email by ID',
            'GET /emails/unread - Get unread emails',
            'GET /emails/important - Get important emails',
            'POST /emails/send - Send new email'
        ]
    })

@app.route('/emails', methods=['GET'])
def get_emails():
    return jsonify({
        'emails': EMAILS,
        'count': len(EMAILS),
        'unread_count': len([e for e in EMAILS if not e['read']])
    })

@app.route('/emails/<int:email_id>', methods=['GET'])
def get_email(email_id):
    email = next((e for e in EMAILS if e['id'] == email_id), None)
    if email:
        return jsonify(email)
    return jsonify({'error': 'Email not found'}), 404

@app.route('/emails/unread', methods=['GET'])
def get_unread_emails():
    unread_emails = [e for e in EMAILS if not e['read']]
    return jsonify({
        'emails': unread_emails,
        'count': len(unread_emails)
    })

@app.route('/emails/important', methods=['GET'])
def get_important_emails():
    important_emails = [e for e in EMAILS if e.get('important', False)]
    return jsonify({
        'emails': important_emails,
        'count': len(important_emails)
    })

@app.route('/emails/send', methods=['POST'])
def send_email():
    data = request.get_json()
    if not data or 'to' not in data or 'subject' not in data:
        return jsonify({'error': 'To and subject are required'}), 400
    
    new_email = {
        'id': max([e['id'] for e in EMAILS]) + 1,
        'from': data.get('from', 'user@company.com'),
        'to': data['to'],
        'subject': data['subject'],
        'body': data.get('body', ''),
        'sent': datetime.utcnow().isoformat() + 'Z',
        'status': 'sent'
    }
    
    return jsonify({
        'message': 'Email sent successfully',
        'email': new_email
    }), 201

@app.route('/emails/stats', methods=['GET'])
def get_email_stats():
    total_emails = len(EMAILS)
    unread_count = len([e for e in EMAILS if not e['read']])
    important_count = len([e for e in EMAILS if e.get('important', False)])
    
    return jsonify({
        'total_emails': total_emails,
        'unread_emails': unread_count,
        'important_emails': important_count,
        'read_emails': total_emails - unread_count
    })

if __name__ == '__main__':
    port = int(os.getenv('SERVICE_PORT', 5004))
    logger.info(f"Starting Outlook Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
