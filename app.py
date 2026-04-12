from flask import Flask, render_template, request, jsonify, session
import json, os, requests, uuid
from datetime import datetime

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.jinja_env.auto_reload = True
app.config['TEMPLATES_FOLDER'] = os.path.join(os.path.dirname(__file__), 'templates')
app.secret_key = 'chatrans_secret_2026'

DATA_FILE = os.path.join(os.path.dirname(__file__), 'data.json')

def load_data():
    if not os.path.exists(DATA_FILE):
        return {'scenes': [], 'settings': {'provider': 'claude', 'claude_key': '', 'openai_key': '', 'gemini_key': '', 'model': ''}}
    with open(DATA_FILE) as f:
        return json.load(f)

def save_data(data):
    os.makedirs(os.path.dirname(DATA_FILE), exist_ok=True)
    with open(DATA_FILE, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

TONE_PROMPTS = {
    'formal':    '使用非常正式的敬语（丁寧語・尊敬語），适合商务或初次见面的场合',
    'normal':    '使用普通礼貌的语气（普通体），日常正常交流',
    'friend':    '使用轻松随意的朋友语气（友達口調），亲切自然',
    'funny':     '使用幽默搞笑的语气，可以加入日语网络流行语，活泼有趣',
    'flirty':    '使用调皮轻浮、暧昧的语气，老不正经风格',
    'arrogant':  '使用俯视对方、略带不屑的语气（上から目線），傲娇风格',
}

TONE_NAMES = {
    'formal': '🫡 正式敬语',
    'normal': '🤝 普通正常',
    'friend': '😊 朋友轻松',
    'funny':  '🎭 搞笑逗趣',
    'flirty': '😏 老不正经',
    'arrogant': '👑 俯视不屑',
}

def call_ai(system_prompt, user_message, settings):
    provider = settings.get('provider', 'claude')

    if provider == 'claude':
        key = settings.get('claude_key', '')
        model = settings.get('claude_model', 'claude-sonnet-4-5') or 'claude-sonnet-4-5'
        headers = {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'}
        body = {'model': model, 'max_tokens': 1024,
                'system': system_prompt,
                'messages': [{'role': 'user', 'content': user_message}]}
        r = requests.post('https://api.anthropic.com/v1/messages', headers=headers, json=body, timeout=30)
        r.raise_for_status()
        return r.json()['content'][0]['text']

    elif provider == 'openai':
        key = settings.get('openai_key', '')
        model = settings.get('openai_model', 'gpt-4o') or 'gpt-4o'
        headers = {'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'}
        body = {'model': model, 'messages': [
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': user_message}
        ]}
        r = requests.post('https://api.openai.com/v1/chat/completions', headers=headers, json=body, timeout=30)
        r.raise_for_status()
        return r.json()['choices'][0]['message']['content']

    elif provider == 'gemini':
        key = settings.get('gemini_key', '')
        model = settings.get('gemini_model', 'gemini-2.0-flash') or 'gemini-2.0-flash'
        url = f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}'
        body = {'contents': [{'parts': [{'text': system_prompt + '\n\n' + user_message}]}]}
        r = requests.post(url, json=body, timeout=30)
        r.raise_for_status()
        return r.json()['candidates'][0]['content']['parts'][0]['text']

    raise ValueError(f'Unknown provider: {provider}')

@app.route('/')
def index():
    from flask import make_response
    resp = make_response(render_template('index.html'))
    resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    resp.headers['Pragma'] = 'no-cache'
    resp.headers['Expires'] = '0'
    return resp

@app.route('/api/scenes', methods=['GET'])
def get_scenes():
    data = load_data()
    return jsonify(data.get('scenes', []))

@app.route('/api/scenes', methods=['POST'])
def create_scene():
    data = load_data()
    scene = request.json
    scene['id'] = str(uuid.uuid4())
    scene['messages'] = []
    scene['created_at'] = datetime.now().isoformat()
    data['scenes'].append(scene)
    save_data(data)
    return jsonify(scene)

@app.route('/api/scenes/<sid>', methods=['DELETE'])
def delete_scene(sid):
    data = load_data()
    data['scenes'] = [s for s in data['scenes'] if s['id'] != sid]
    save_data(data)
    return jsonify({'ok': True})

@app.route('/api/scenes/<sid>/messages', methods=['GET'])
def get_messages(sid):
    data = load_data()
    scene = next((s for s in data['scenes'] if s['id'] == sid), None)
    if not scene:
        return jsonify([])
    return jsonify(scene.get('messages', []))

@app.route('/api/translate/incoming', methods=['POST'])
def translate_incoming():
    """翻译对方说的话"""
    body = request.json
    sid = body.get('scene_id')
    text = body.get('text', '')
    data = load_data()
    scene = next((s for s in data['scenes'] if s['id'] == sid), {})
    settings = data.get('settings', {})

    context = scene.get('context', '')
    other_lang = scene.get('other_lang', '日语')
    other_name = scene.get('name', '对方')

    system = f"""你是翻译助手。严格按以下格式回复，不要加任何额外内容：

【翻译】
（把对方的话翻译成中文，直接写翻译结果）

【备注】
（一句话说明语气，例如：语气轻松自然）"""
    try:
        result = call_ai(system, f'对方说：{text}', settings)
        # 保存消息
        msg = {'id': str(uuid.uuid4()), 'type': 'incoming', 'original': text,
               'translation': result, 'timestamp': datetime.now().isoformat()}
        scene.setdefault('messages', []).append(msg)
        save_data(data)
        return jsonify({'ok': True, 'result': result, 'msg_id': msg['id']})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500

@app.route('/api/translate/outgoing', methods=['POST'])
def translate_outgoing():
    """把我想说的中文翻译成对方语言"""
    body = request.json
    sid = body.get('scene_id')
    text = body.get('text', '')
    data = load_data()
    scene = next((s for s in data['scenes'] if s['id'] == sid), {})
    settings = data.get('settings', {})

    context = scene.get('context', '')
    other_lang = scene.get('other_lang', '日语')
    other_name = scene.get('name', '对方')
    tone = scene.get('tone', 'normal')
    tone_desc = TONE_PROMPTS.get(tone, TONE_PROMPTS['normal'])

    # 获取最近几条对话上下文
    messages = scene.get('messages', [])[-6:]
    history = ''
    for m in messages:
        if m['type'] == 'incoming':
            history += f'对方说：{m["original"]}\n'
        elif m['type'] == 'outgoing':
            history += f'我说：{m.get("original","")}\n'

    system = f"""你是翻译助手。背景：{context if context else "无"}
对方是{other_name}，我用{other_lang}回复，语气要求：{tone_desc}

把我的中文翻译成{other_lang}，给出3条不同说法。
重要：只输出3条{other_lang}文本，用|||分隔，不要编号，不要中文说明，格式如下：
第一条日语===第二条日语===第三条日语"""
    try:
        result = call_ai(system, f'我想说：{text}', settings)
        msg = {'id': str(uuid.uuid4()), 'type': 'outgoing', 'original': text,
               'translation': result, 'timestamp': datetime.now().isoformat()}
        scene.setdefault('messages', []).append(msg)
        save_data(data)
        return jsonify({'ok': True, 'result': result, 'msg_id': msg['id']})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)}), 500

@app.route('/api/settings', methods=['GET'])
def get_settings():
    data = load_data()
    s = data.get('settings', {})
    # 隐藏key的中间部分
    def mask(k):
        if not k: return ''
        return k[:6] + '****' + k[-4:] if len(k) > 10 else '****'
    return jsonify({
        'provider': s.get('provider', 'claude'),
        'claude_key_masked': mask(s.get('claude_key','')),
        'openai_key_masked': mask(s.get('openai_key','')),
        'gemini_key_masked': mask(s.get('gemini_key','')),
        'claude_model': s.get('claude_model', 'claude-sonnet-4-5'),
        'openai_model': s.get('openai_model', 'gpt-4o'),
        'gemini_model': s.get('gemini_model', 'gemini-2.0-flash'),
        'has_claude': bool(s.get('claude_key','')),
        'has_openai': bool(s.get('openai_key','')),
        'has_gemini': bool(s.get('gemini_key','')),
    })

@app.route('/api/settings', methods=['POST'])
def save_settings():
    data = load_data()
    body = request.json
    s = data.setdefault('settings', {})
    if 'provider' in body: s['provider'] = body['provider']
    if 'claude_key' in body and body['claude_key'] and '****' not in body['claude_key']:
        s['claude_key'] = body['claude_key']
    if 'openai_key' in body and body['openai_key'] and '****' not in body['openai_key']:
        s['openai_key'] = body['openai_key']
    if 'gemini_key' in body and body['gemini_key'] and '****' not in body['gemini_key']:
        s['gemini_key'] = body['gemini_key']
    if 'claude_model' in body: s['claude_model'] = body['claude_model']
    if 'openai_model' in body: s['openai_model'] = body['openai_model']
    if 'gemini_model' in body: s['gemini_model'] = body['gemini_model']
    save_data(data)
    return jsonify({'ok': True})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8090, debug=False)
