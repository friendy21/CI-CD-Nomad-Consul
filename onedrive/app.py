from flask import Flask, jsonify, request
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Sample file data
FILES = [
    {
        "id": 1,
        "name": "Project Proposal.docx",
        "size": 2048576,
        "type": "document",
        "modified": "2024-08-20T10:30:00Z",
        "owner": "john.doe@company.com",
        "shared": True
    },
    {
        "id": 2,
        "name": "Budget Report.xlsx",
        "size": 1024000,
        "type": "spreadsheet",
        "modified": "2024-08-21T14:15:00Z",
        "owner": "alice.brown@company.com",
        "shared": False
    },
    {
        "id": 3,
        "name": "Presentation.pptx",
        "size": 5242880,
        "type": "presentation",
        "modified": "2024-08-21T16:45:00Z",
        "owner": "jane.smith@company.com",
        "shared": True
    }
]

FOLDERS = [
    {"id": 1, "name": "Projects", "file_count": 15},
    {"id": 2, "name": "Reports", "file_count": 8},
    {"id": 3, "name": "Templates", "file_count": 12}
]

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'service': 'onedrive-service',
        'version': os.getenv('VERSION', '1.0.0'),
        'timestamp': datetime.utcnow().isoformat(),
        'port': os.getenv('SERVICE_PORT', '5003')
    })

@app.route('/')
def home():
    return jsonify({
        'message': 'OneDrive Service API',
        'version': os.getenv('VERSION', '1.0.0'),
        'service': os.getenv('SERVICE_NAME', 'onedrive-service'),
        'endpoints': [
            'GET /health - Health check',
            'GET /files - List all files',
            'GET /files/<id> - Get file by ID',
            'GET /folders - List all folders',
            'GET /files/shared - Get shared files',
            'GET /storage - Get storage info'
        ]
    })

@app.route('/files', methods=['GET'])
def get_files():
    return jsonify({
        'files': FILES,
        'count': len(FILES)
    })

@app.route('/files/<int:file_id>', methods=['GET'])
def get_file(file_id):
    file = next((f for f in FILES if f['id'] == file_id), None)
    if file:
        return jsonify(file)
    return jsonify({'error': 'File not found'}), 404

@app.route('/folders', methods=['GET'])
def get_folders():
    return jsonify({
        'folders': FOLDERS,
        'count': len(FOLDERS)
    })

@app.route('/files/shared', methods=['GET'])
def get_shared_files():
    shared_files = [f for f in FILES if f.get('shared', False)]
    return jsonify({
        'files': shared_files,
        'count': len(shared_files)
    })

@app.route('/storage', methods=['GET'])
def get_storage_info():
    total_size = sum(f['size'] for f in FILES)
    return jsonify({
        'total_files': len(FILES),
        'total_size_bytes': total_size,
        'total_size_mb': round(total_size / 1024 / 1024, 2),
        'folders': len(FOLDERS),
        'shared_files': len([f for f in FILES if f.get('shared', False)])
    })

if __name__ == '__main__':
    port = int(os.getenv('SERVICE_PORT', 5003))
    logger.info(f"Starting OneDrive Service on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
