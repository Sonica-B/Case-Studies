#!/usr/bin/env python3
"""
Smart Proxy with Cookie-based Model Selection
Remembers user's model preference and routes accordingly
"""

from flask import Flask, request, make_response, redirect, jsonify
import requests
from requests.adapters import HTTPAdapter
from urllib.parse import urlparse
import os

app = Flask(__name__)

# Backend services
SERVICES = {
    'api': 'http://localhost:5000',
    'local': 'http://localhost:5003'
}

# Create session with connection pooling
session = requests.Session()
adapter = HTTPAdapter(pool_connections=10, pool_maxsize=10)
session.mount('http://', adapter)

@app.route('/')
def index():
    """Main page with model selector"""
    current_model = request.cookies.get('model_preference', 'api')

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Smart Model Gateway</title>
        <style>
            body {{
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                margin: 0;
                padding: 20px;
                min-height: 100vh;
            }}
            .container {{
                max-width: 900px;
                margin: auto;
                background: white;
                border-radius: 15px;
                padding: 30px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            }}
            h1 {{
                color: #333;
                text-align: center;
            }}
            .toggle-container {{
                display: flex;
                justify-content: center;
                margin: 30px 0;
            }}
            .toggle {{
                position: relative;
                display: inline-block;
                width: 200px;
                height: 40px;
                background: #ddd;
                border-radius: 20px;
                cursor: pointer;
            }}
            .toggle-slider {{
                position: absolute;
                top: 5px;
                left: {'105px' if current_model == 'local' else '5px'};
                width: 90px;
                height: 30px;
                background: {'#4CAF50' if current_model == 'api' else '#2196F3'};
                border-radius: 15px;
                transition: all 0.3s;
                display: flex;
                align-items: center;
                justify-content: center;
                color: white;
                font-weight: bold;
            }}
            .status {{
                text-align: center;
                padding: 20px;
                background: #f0f0f0;
                border-radius: 10px;
                margin: 20px 0;
            }}
            .model-info {{
                display: flex;
                justify-content: space-around;
                margin: 30px 0;
            }}
            .model-card {{
                flex: 1;
                margin: 0 10px;
                padding: 20px;
                border: 2px solid #ddd;
                border-radius: 10px;
                text-align: center;
            }}
            .model-card.active {{
                border-color: #4CAF50;
                background: #f0fff0;
            }}
            .access-btn {{
                display: inline-block;
                margin: 20px auto;
                padding: 15px 30px;
                background: linear-gradient(45deg, #667eea, #764ba2);
                color: white;
                text-decoration: none;
                border-radius: 25px;
                font-size: 18px;
                transition: transform 0.3s;
            }}
            .access-btn:hover {{
                transform: scale(1.05);
            }}
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🚀 Smart Model Gateway</h1>

            <div class="status">
                <h3>Current Model: <span style="color: {'#4CAF50' if current_model == 'api' else '#2196F3'}">
                    {current_model.upper()}</span>
                </h3>
            </div>

            <div class="toggle-container">
                <div class="toggle" onclick="toggleModel()">
                    <div class="toggle-slider" id="slider">
                        {current_model.upper()}
                    </div>
                </div>
            </div>

            <div class="model-info">
                <div class="model-card {'active' if current_model == 'api' else ''}">
                    <h3>📡 API Model</h3>
                    <p><strong>CLIP via HuggingFace</strong></p>
                    <p>✅ Fast inference</p>
                    <p>✅ Low resource usage</p>
                    <p>❌ Requires internet</p>
                </div>
                <div class="model-card {'active' if current_model == 'local' else ''}">
                    <h3>💻 Local Model</h3>
                    <p><strong>Wav2Vec2 + CLIP</strong></p>
                    <p>✅ Complete privacy</p>
                    <p>✅ Works offline</p>
                    <p>❌ Higher resource usage</p>
                </div>
            </div>

            <center>
                <a href="/app" class="access-btn">Access Model Interface →</a>
            </center>

            <div style="margin-top: 30px; padding: 20px; background: #f9f9f9; border-radius: 10px;">
                <h4>🎯 How it works:</h4>
                <ul>
                    <li>Toggle between models anytime - your preference is saved</li>
                    <li>Both models remain running in the background</li>
                    <li>Seamless switching with no downtime</li>
                    <li>Single URL for both models: just <code>/app</code></li>
                </ul>
            </div>
        </div>

        <script>
            function toggleModel() {{
                fetch('/toggle', {{method: 'POST'}})
                    .then(response => response.json())
                    .then(data => {{
                        location.reload();
                    }});
            }}
        </script>
    </body>
    </html>
    """
    return html

@app.route('/toggle', methods=['POST'])
def toggle_model():
    """Toggle between API and Local models"""
    current = request.cookies.get('model_preference', 'api')
    new_model = 'local' if current == 'api' else 'api'

    response = make_response(jsonify({'model': new_model}))
    response.set_cookie('model_preference', new_model, max_age=86400*30)  # 30 days
    return response

@app.route('/app')
@app.route('/app/<path:path>')
def proxy_app(path=''):
    """Proxy requests to the selected model"""
    model = request.cookies.get('model_preference', 'api')
    backend_url = SERVICES[model]

    # Forward the request
    try:
        # Build the target URL
        target_url = f"{backend_url}/{path}"
        if request.query_string:
            target_url += f"?{request.query_string.decode()}"

        # Forward the request based on method
        if request.method == 'GET':
            resp = session.get(target_url, headers=request.headers)
        elif request.method == 'POST':
            resp = session.post(target_url, data=request.data, headers=request.headers)
        else:
            resp = session.request(
                method=request.method,
                url=target_url,
                headers=request.headers,
                data=request.data
            )

        # Create response
        response = make_response(resp.content)
        response.status_code = resp.status_code

        # Copy headers (except problematic ones)
        exclude_headers = ['content-encoding', 'content-length', 'transfer-encoding', 'connection']
        for key, value in resp.headers.items():
            if key.lower() not in exclude_headers:
                response.headers[key] = value

        return response

    except Exception as e:
        return jsonify({'error': str(e), 'model': model}), 500

@app.route('/health')
def health():
    """Health check endpoint"""
    status = {}
    for name, url in SERVICES.items():
        try:
            r = session.get(f"{url}/health", timeout=2)
            status[name] = 'healthy' if r.status_code == 200 else 'unhealthy'
        except:
            status[name] = 'offline'

    current_model = request.cookies.get('model_preference', 'api')
    return jsonify({
        'gateway': 'healthy',
        'current_model': current_model,
        'services': status
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=False)