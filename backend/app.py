import pandas as pd
import numpy as np
import joblib
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import speech_recognition as sr
from sklearn.ensemble import RandomForestClassifier
from sklearn.neural_network import MLPClassifier
from xgboost import XGBClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.pipeline import make_pipeline
from symptom_phrases_marathi import SYMPTOM_PHRASES_MARATHI
from disease_precautions import DISEASE_PRECAUTIONS
from flask import Flask, request, jsonify, session
from rapidfuzz import fuzz
import os
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
import json
from datetime import datetime
from sqlalchemy.orm import relationship
from sqlalchemy import ForeignKey
from flask_cors import CORS


app = Flask(__name__)

app.config['SECRET_KEY'] = 'arogyamitra_secret_key'  # change later for production
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///users.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
CORS(app)

db = SQLAlchemy(app)

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    age = db.Column(db.Integer, nullable=True)
    gender = db.Column(db.String(20), nullable=True)

class Conversation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(255), nullable=True)
    user_email = db.Column(db.String(120), nullable=False)  # owner
    created_at = db.Column(db.String(64), default=lambda: datetime.utcnow().isoformat())
    # relationship for convenience
    messages = relationship('Message', backref='conversation', cascade='all, delete-orphan')

class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    conversation_id = db.Column(db.Integer, ForeignKey('conversation.id'), nullable=False)
    message = db.Column(db.Text, nullable=False)
    is_user = db.Column(db.Boolean, default=False)
    timestamp = db.Column(db.String(64), default=lambda: datetime.utcnow().isoformat())
    disease = db.Column(db.String(255), nullable=True)
    precautions = db.Column(db.Text, nullable=True)
    symptoms = db.Column(db.Text, nullable=True)  # JSON encoded list


class DiseasePredictor:
    def __init__(self):
        self.rf_model = None
        self.label_encoder = None
        self.symptoms_list = []
        self.disease_precautions = {}
        self.model_dir = 'model'
        self.df = None
        self.load_data()
        self.load_precautions()

        # Load pre-trained RF model and encoder if available
        try:
            rf_path = os.path.join(self.model_dir, 'rf_model.pkl')
            le_path = os.path.join(self.model_dir, 'label_encoder.pkl')

            if all(os.path.exists(p) for p in [rf_path, le_path]):
                try:
                    self.rf_model = joblib.load(rf_path)
                    self.label_encoder = joblib.load(le_path)
                    if self.are_saved_artifacts_compatible():
                        print("✓ Loaded saved Random Forest model and label encoder from disk.")
                        return
                    print("⚠️ Saved Random Forest/encoder incompatible. Retraining.")
                except Exception as e:
                    print(f"⚠️ Failed to load saved Random Forest: {e}. Will retrain.")
        except Exception:
            pass

        # Train model if not loaded
        self.train_model()

    def _get_model_feature_count(self, model):
        if hasattr(model, 'n_features_in_'):
            return int(model.n_features_in_)
        if hasattr(model, 'named_steps') and model.named_steps:
            last_step = list(model.named_steps.values())[-1]
            if hasattr(last_step, 'n_features_in_'):
                return int(last_step.n_features_in_)
        return None

    def are_saved_artifacts_compatible(self):
        if self.df is None or self.label_encoder is None:
            return False

        dataset_diseases = set(self.df.index.astype(str).unique().tolist())
        encoder_diseases = set([str(x) for x in self.label_encoder.classes_])
        if dataset_diseases != encoder_diseases:
            return False

        expected_features = len(self.symptoms_list)
        feature_count = getattr(self.rf_model, 'n_features_in_', None)
        if feature_count != expected_features:
            return False

        return True

    def load_data(self):
        try:
            self.df = pd.read_csv('data/Marathi_Training.csv', encoding='utf-8', index_col=0)
            self.df.columns = self.df.columns.str.strip()
            for col in self.df.columns:
                self.df[col] = pd.to_numeric(self.df[col], errors='coerce').fillna(0).astype(int)
            self.symptoms_list = self.df.columns.tolist()
            diseases = self.df.index.astype(str)
            le_path = os.path.join(self.model_dir, 'label_encoder.pkl')
            if os.path.exists(le_path):
                self.label_encoder = joblib.load(le_path)
            else:
                self.label_encoder = LabelEncoder()
                self.label_encoder.fit(diseases)
        except Exception as e:
            print(f"✗ Error loading dataset: {e}")

    def train_model(self):
        try:
            X = self.df[self.symptoms_list].fillna(0).astype(int)
            y = self.label_encoder.transform(self.df.index)

            X_train, X_test, y_train, y_test = train_test_split(
                X, y, test_size=0.2, random_state=42, stratify=y
            )

            self.rf_model = RandomForestClassifier(
                n_estimators=100,
                random_state=42,
                max_depth=10,
                min_samples_split=5,
                min_samples_leaf=2
            )
            print("Training Random Forest model...")
            self.rf_model.fit(X_train, y_train)

            os.makedirs(self.model_dir, exist_ok=True)
            joblib.dump(self.rf_model, os.path.join(self.model_dir, 'rf_model.pkl'))
            joblib.dump(self.label_encoder, os.path.join(self.model_dir, 'label_encoder.pkl'))

            print("✓ Random Forest trained and saved successfully.")

        except Exception as e:
            print(f"✗ Error training Random Forest: {e}")

    def load_precautions(self):
        self.disease_precautions = DISEASE_PRECAUTIONS

    def clean_and_extract_symptoms(self, marathi_text):
        detected_symptoms = []
        marathi_text = marathi_text.strip().lower()

        # Debug 1
        print("Input text:", marathi_text)
        for symptom, phrases in SYMPTOM_PHRASES_MARATHI.items():
            for phrase in phrases:

                # Exact match (fast)
                if phrase in marathi_text:
                    detected_symptoms.append(symptom)
                    break

                # Fuzzy match
                similarity = fuzz.partial_ratio(phrase, marathi_text)

                if similarity > 85:
                    print(f"Fuzzy matched '{phrase}' with score {similarity}")
                    detected_symptoms.append(symptom)
                    break

        # Debug 2
        print("Detected symptoms:", detected_symptoms)
        return list(set(detected_symptoms))

    def predict_disease(self, symptoms):
        try:
            if not symptoms or not self.rf_model or not self.label_encoder:
                return None, 0.0, symptoms

            input_vector = [1 if s in symptoms else 0 for s in self.symptoms_list]
            input_df = pd.DataFrame([input_vector], columns=self.symptoms_list)

            probs_rf = self.rf_model.predict_proba(input_df)
            final_prediction_index = int(np.argmax(probs_rf, axis=1)[0])
            probability = float(np.max(probs_rf, axis=1)[0])
            predicted_disease = self.label_encoder.classes_[final_prediction_index]

            return predicted_disease, probability, symptoms

        except Exception as e:
            print(f"✗ Error during prediction: {e}")
            return None, 0.0, symptoms


# Initialize predictor
predictor = DiseasePredictor()

def get_current_user():
    """Helper to get user from session or request parameters (for mobile clients)"""
    # 1. Check session
    user = session.get('user')
    if user:
        return user

    # 2. Check query parameters (common for GET)
    email = request.args.get('email')
    if email:
        return email

    # 3. Check JSON body (common for POST)
    if request.is_json:
        try:
            data = request.get_json(silent=True)
            if data and 'email' in data:
                return data.get('email')
        except:
            pass

    return None

@app.route('/api/signup', methods=['POST'])
def signup():
    data = request.get_json()
    name = data.get('name')
    email = data.get('email')
    password = data.get('password')
    age = data.get('age')
    gender = data.get('gender')

    if not (name and email and password):
        return jsonify({"success": False, "message": "सर्व फील्ड भरा"}), 400

    if User.query.filter_by(email=email).first():
        return jsonify({"success": False, "message": "ईमेल आधीच नोंदणीकृत आहे"}), 409

    hashed_pw = generate_password_hash(password)
    new_user = User(
        name=name,
        email=email,
        password_hash=hashed_pw,
        age=age,
        gender=gender
    )
    db.session.add(new_user)
    db.session.commit()

    session['user'] = email
    return jsonify({"success": True, "message": "नोंदणी यशस्वी"}), 201

@app.route('/api/login', methods=['POST'])
def login():
    print("📥 Login route hit") #debug
    data = request.get_json()
    print("Received data:", data) #debug
    email = data.get('email')
    password = data.get('password')

    user = User.query.filter_by(email=email).first()
    if not user or not check_password_hash(user.password_hash, password):
        return jsonify({"success": False, "message": "चुकीचे ईमेल किंवा पासवर्ड"}), 401

    session['user'] = email
    return jsonify({"success": True, "message": "लॉगिन यशस्वी"}), 200

@app.route('/api/logout', methods=['POST'])
def logout():
    session.pop('user', None)
    return jsonify({"success": True, "message": "लॉगआउट यशस्वी"}), 200

@app.route('/api/profile', methods=['GET'])
def get_profile():
    user_email = get_current_user()
    if not user_email:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    user = User.query.filter_by(email=user_email).first()
    if not user:
        return jsonify({'success': False, 'message': 'User not found'}), 404

    return jsonify({
        'success': True,
        'name': user.name,
        'email': user.email,
        'age': user.age,
        'gender': user.gender
    })

@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

@app.route('/api/symptoms', methods=['GET'])
def get_symptoms():
    return jsonify({
        'symptoms': predictor.symptoms_list,
        'count': len(predictor.symptoms_list),
        'language': 'marathi'
    })

@app.route('/api/diseases', methods=['GET'])
def get_diseases():
    diseases = predictor.label_encoder.classes_.tolist() if predictor.label_encoder else []
    return jsonify({
        'diseases': diseases,
        'count': len(diseases),
        'language': 'marathi'
    })


@app.route('/api/predict', methods=['POST'])
def predict_disease_api():
    try:
        data = request.json
        text = data.get('text', '')
        conversation_id = data.get('conversation_id')
        if not text:
            return jsonify({'success': False, 'error': 'No text provided'})

        print(f"📥 Received prediction request: '{text}'")

        symptoms = predictor.clean_and_extract_symptoms(text)
        if not symptoms:
            return jsonify({
                'success': False,
                'error_marathi': "माफ करा, लक्षणे सापडली नाहीत. कृपया अधिक तपशील द्या.",
                'suggested_symptoms': predictor.symptoms_list[:10]
            })

        disease, probability, detected_symptoms = predictor.predict_disease(symptoms)
        # Update conversation title with predicted disease
        if conversation_id:
            conv = Conversation.query.get(conversation_id)
            if conv:
                conv.title = disease
                db.session.commit()

        raw_prec = predictor.disease_precautions.get(disease, ["डॉक्टरांचा सल्ला घ्या."])
        precautions_list = []

        if isinstance(raw_prec, dict):
            for v in raw_prec.values():
                if isinstance(v, list):
                    precautions_list.extend(v)
                elif isinstance(v, str):
                    precautions_list.append(v)
        elif isinstance(raw_prec, list):
            precautions_list = list(raw_prec)
        elif isinstance(raw_prec, str):
            precautions_list = [raw_prec]
        else:
            precautions_list = ["डॉक्टरांचा सल्ला घ्या."]

        seen = set()
        deduped = []
        for p in precautions_list:
            if not p:
                continue
            s = str(p).strip()
            if s and s not in seen:
                seen.add(s)
                deduped.append(s)
        precautions_list = deduped

        confidence_level = "उच्च" if probability > 0.7 else "मध्यम" if probability > 0.4 else "कमी"

        return jsonify({
             'success': True,
             'symptoms_detected': symptoms,
             'disease_marathi': disease,
             'probability': probability,
             'confidence': confidence_level,
             'precautions_marathi': precautions_list,
             'message': f'तुमच्या लक्षणांवरून, तुम्हाला {disease} असू शकते.'
         })

    except Exception as e:
        print(f"💥 Prediction endpoint error: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/speech-to-text', methods=['POST'])
def speech_to_text():
    try:
        if not request.data:
            return jsonify({'success': False, 'error': 'No audio data provided'})

        import tempfile
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_audio:
            temp_audio.write(request.data)
            temp_audio_path = temp_audio.name

        r = sr.Recognizer()
        with sr.AudioFile(temp_audio_path) as source:
            audio_data = r.record(source)
            try:
                text = r.recognize_google(audio_data, language='mr-IN')
                print(f"🎤 Speech recognized: {text}")
                result = {'success': True, 'text': text, 'language': 'marathi'}
            except sr.UnknownValueError:
                result = {'success': False, 'error': 'ध्वनी समजू शकला नाही. कृपया स्पष्ट मराठीत बोला.'}
            except sr.RequestError as e:
                result = {'success': False, 'error': f'ध्वनी ओळख सेवा त्रुटी: {e}'}
            except Exception as e:
                result = {'success': False, 'error': f'ध्वनी ओळख अयशस्वी: {str(e)}'}

        try:
            os.unlink(temp_audio_path)
        except:
            pass
        return jsonify(result)
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/conversations', methods=['POST'])
def create_conversation():
    user = get_current_user()
    if not user:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    data = request.get_json() or {}
    title = data.get('title') or f'Conversation {datetime.utcnow().isoformat()}'
    conv = Conversation(title=title, user_email=user)
    db.session.add(conv)
    db.session.commit()
    return jsonify({'success': True, 'id': conv.id, 'title': conv.title}), 201

@app.route('/api/conversations', methods=['GET'])
def list_conversations():
    user = get_current_user()
    if not user:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    convs = Conversation.query.filter_by(user_email=user).order_by(Conversation.id.desc()).all()
    out = []
    for c in convs:
        last_msg = c.messages[-1].message if c.messages else None
        out.append({
            'id': c.id,
            'title': c.title,
            'created_at': c.created_at,
            'lastMessage': last_msg
        })
    return jsonify({'success': True, 'conversations': out})

@app.route('/api/conversations/<int:conv_id>/messages', methods=['GET'])
def get_messages(conv_id):
    user = get_current_user()
    if not user:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    conv = Conversation.query.filter_by(id=conv_id, user_email=user).first()
    if not conv:
        return jsonify({'success': False, 'message': 'Not found'}), 404

    msgs = []
    for m in conv.messages:
        msgs.append({
            'id': m.id,
            'message': m.message,
            'is_user': m.is_user,
            'timestamp': m.timestamp,
            'disease': m.disease,
            'precautions': json.loads(m.precautions) if m.precautions else None,
            'symptoms': json.loads(m.symptoms) if m.symptoms else None
        })
    return jsonify({'success': True, 'messages': msgs})

@app.route('/api/conversations/<int:conv_id>/messages', methods=['POST'])
def add_message(conv_id):
    user = get_current_user()
    if not user:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    conv = Conversation.query.filter_by(id=conv_id, user_email=user).first()
    if not conv:
        return jsonify({'success': False, 'message': 'Conversation not found'}), 404

    data = request.get_json() or {}
    msg_text = data.get('message')
    is_user = bool(data.get('is_user', False))
    disease = data.get('disease')
    precautions = data.get('precautions')
    symptoms = data.get('symptoms')

    if msg_text is None:
        return jsonify({'success': False, 'message': 'message required'}), 400

    m = Message(
        conversation_id=conv.id,
        message=msg_text,
        is_user=is_user,
        disease=disease,
        precautions=json.dumps(precautions) if precautions is not None else None,
        symptoms=json.dumps(symptoms) if symptoms is not None else None
    )
    db.session.add(m)
    db.session.commit()
    return jsonify({'success': True, 'id': m.id}), 201

@app.route('/api/conversations/<int:conv_id>', methods=['DELETE'])
def delete_conversation(conv_id):
    user = get_current_user()
    if not user:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    conv = Conversation.query.filter_by(id=conv_id, user_email=user).first()
    if not conv:
        return jsonify({'success': False, 'message': 'Not found'}), 404

    db.session.delete(conv)
    db.session.commit()
    return jsonify({'success': True, 'message': 'Deleted'})

def create_tables():
    with app.app_context():
        db.create_all()

create_tables()

if __name__ == '__main__':
    os.makedirs('model', exist_ok=True)
    os.makedirs('data', exist_ok=True)

    print("🌐 AarogyaMitra Marathi Backend Server Starting...")
    print("📍 Health check: http://localhost:5000/api/health")
    print("📍 Symptoms list: http://localhost:5000/api/symptoms")
    print("📍 Diseases list: http://localhost:5000/api/diseases")
    print("📍 Prediction API: POST http://localhost:5000/api/predict")
    print("\n🚀 Server running on http://localhost:5000")
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=False)
