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
from flask import Flask, request, jsonify
import os
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from flask import session
import json
from datetime import datetime
from sqlalchemy.orm import relationship
from sqlalchemy import ForeignKey


app = Flask(__name__)

app.config['SECRET_KEY'] = 'arogyamitra_secret_key'  # change later for production
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///users.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)

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
        self.xgb_model = None
        self.mlp_model = None
        self.label_encoder = None
        self.symptoms_list = []
        self.disease_precautions = {}
        self.model_dir = 'model'
        self.df = None
        self.load_data()
        self.load_precautions()
        self.train_model()

    def load_data(self):
        try:
            # Read CSV, explicitly setting the first column (disease names) as string type
            self.df = pd.read_csv('data/disease_symptoms.csv', encoding='utf-8', header = 0)
            self.df = self.df.reset_index()
            #print(f"🔍 DEBUG: Original unique disease names after CSV load: {self.df.iloc[:, 0].unique().tolist()}")

            # Ensure the disease column is explicitly string type
            self.df.iloc[:, 0] = self.df.iloc[:, 0].astype(str)
            self.symptoms_list = self.df.columns[1:].tolist()
            print(f"✓ Loaded Marathi dataset with {len(self.df)} records and {len(self.symptoms_list)} symptoms")

            # Try loading label encoder from model dir
            le_path = os.path.join(self.model_dir, 'label_encoder.pkl')
            if os.path.exists(le_path):
                try:
                    self.label_encoder = joblib.load(le_path)
                    if not hasattr(self.label_encoder, "classes_"):
                        raise ValueError("LabelEncoder is not fitted properly.")
                    #print(f"🔍 DEBUG: LabelEncoder classes loaded from file: {self.label_encoder.classes_.tolist()}")
                    print(f"✓ LabelEncoder classes loaded: {len(self.label_encoder.classes_)} diseases")
                    return
                except Exception as e:
                    print(f"⚠️ LabelEncoder error ({e}). Recreating encoder from dataset...")

            # Create new label encoder if file not found or invalid
            self.label_encoder = LabelEncoder()
            y = self.df.iloc[:, 0]  # Diseases (in Marathi)
            #print(f"🔍 DEBUG: Unique values in diseases column (y) before encoding: {y.unique().tolist()}")
            self.label_encoder.fit(y)

        except Exception as e:
            print(f"✗ Error loading dataset: {e}")

    def train_model(self):
        try:
            X = self.df.iloc[:, 1:]  # Symptoms
            y = self.df.iloc[:, 0]   # Diseases (in Marathi)

            # Encode string labels to integers for model training
            self.label_encoder = LabelEncoder()
            y_encoded = self.label_encoder.fit_transform(y)
            X = X.fillna(0)
            X = X.astype(int)

            X_train, X_test, y_train, y_test = train_test_split(
                X, y_encoded, test_size=0.2, random_state=42, stratify=y_encoded
            )

            # 1. Random Forest Model
            self.rf_model = RandomForestClassifier(
                n_estimators=100,
                random_state=42,
                max_depth=10,
                min_samples_split=5,
                min_samples_leaf=2
            )
            print("Training RandomForest model...")
            self.rf_model.fit(X_train, y_train)

            # 2. XGBoost Model
            self.xgb_model = XGBClassifier(
                n_estimators=100,
                random_state=42,
                #use_label_encoder=False,
                eval_metric='mlogloss'
            )
            print("Training XGBoost model...")
            self.xgb_model.fit(X_train, y_train)

            # 3. MLP (Neural Network) Model (use scaling + more iterations + early stopping)
            self.mlp_model = make_pipeline(
                StandardScaler(),
                MLPClassifier(
                    hidden_layer_sizes=(100,),
                    max_iter=1000,           # increase iterations
                    tol=1e-4,                # convergence tolerance
                    n_iter_no_change=20,     # patience for early stopping
                    early_stopping=True,     # stop if no improvement on validation set
                    random_state=42,
                    activation='relu',
                    solver='adam',
                    learning_rate_init=0.001,
                    verbose=False
                )
            )
            print("Training MLP (Neural Network) model (with scaling & early stopping)...")
            self.mlp_model.fit(X_train, y_train)

            # Save all models and the label encoder
            os.makedirs(self.model_dir, exist_ok=True)
            joblib.dump(self.rf_model, os.path.join(self.model_dir, 'rf_model.pkl'))
            joblib.dump(self.xgb_model, os.path.join(self.model_dir, 'xgb_model.pkl'))
            joblib.dump(self.mlp_model, os.path.join(self.model_dir, 'mlp_model.pkl'))
            joblib.dump(self.label_encoder, os.path.join(self.model_dir, 'label_encoder.pkl'))
            print("✓ All models trained and saved successfully.")

        except Exception as e:
            print(f"✗ Error training model: {e}")

    def load_precautions(self):
        # Placeholder: Marathi precautions dictionary
        self.disease_precautions = DISEASE_PRECAUTIONS

    def clean_and_extract_symptoms(self, marathi_text):
        detected_symptoms = []
        marathi_text = marathi_text.strip().lower()
        for symptom, phrases in SYMPTOM_PHRASES_MARATHI.items():
            for phrase in phrases:
                if phrase in marathi_text:
                    detected_symptoms.append(symptom)
                    break
        return list(set(detected_symptoms))

    def predict_disease(self, symptoms):
        try:
            if not symptoms:
                return None, 0.0, symptoms

            input_data = {s: [1 if s in symptoms else 0] for s in self.symptoms_list}
            input_df = pd.DataFrame(input_data)

            probs_rf = self.rf_model.predict_proba(input_df)
            probs_xgb = self.xgb_model.predict_proba(input_df)
            probs_mlp = self.mlp_model.predict_proba(input_df)

            final_probs = (0.4 * probs_rf + 0.4 * probs_xgb + 0.2 * probs_mlp)

            final_prediction_index = np.argmax(final_probs)
            probability = np.max(final_probs)

            predicted_disease = "अज्ञात आजार"
            if self.label_encoder and hasattr(self.label_encoder, 'classes_'):
                try:
                    predicted_disease = str(self.label_encoder.inverse_transform([final_prediction_index])[0])
                except Exception:
                    pass

            print(f"✅ Final Prediction: {predicted_disease}, Probability: {probability:.2f}")
            return predicted_disease, probability, symptoms

        except Exception as e:
            print(f"✗ Error during prediction: {e}")
            return None, 0.0, symptoms


# Initialize predictor
predictor = DiseasePredictor()


@app.route('/api/signup', methods=['POST'])
def signup():
    data = request.get_json()
    name = data.get('name')
    email = data.get('email')
    password = data.get('password')

    if not (name and email and password):
        return jsonify({"success": False, "message": "सर्व फील्ड भरा"}), 400

    # check if email already exists
    if User.query.filter_by(email=email).first():
        return jsonify({"success": False, "message": "ईमेल आधीच नोंदणीकृत आहे"}), 409

    hashed_pw = generate_password_hash(password)
    new_user = User(name=name, email=email, password_hash=hashed_pw)
    db.session.add(new_user)
    db.session.commit()

    session['user'] = email
    return jsonify({"success": True, "message": "नोंदणी यशस्वी"}), 201

@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
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
    return jsonify({"success": True, "message": "लॉगआउट झाले"}), 200


@app.route('/api/check-session', methods=['GET'])
def check_session():
    if 'user' in session:
        return jsonify({"authenticated": True, "user": session['user']})
    else:
        return jsonify({"authenticated": False})



@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({
        'status': 'healthy',
        'message': 'AarogyaMitra API is running',
        'symptoms_loaded': len(predictor.symptoms_list) if predictor.symptoms_list else 0,
        'model_trained': all(m is not None for m in [predictor.rf_model, predictor.xgb_model, predictor.mlp_model]),
        'diseases_loaded': len(predictor.label_encoder.classes_) if predictor.label_encoder else 0,
        'language': 'marathi'
    })


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
        # Get precautions from dictionary, handle multiple shapes and deduplicate
        raw_prec = predictor.disease_precautions.get(disease, ["डॉक्टरांचा सल्ला घ्या."])
        precautions_list = []
        # normalize different possible types (dict, list, str)
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

        # strip and remove duplicates while preserving order
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
    """Convert speech audio to text using Google Speech Recognition"""
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
    user = session.get('user')
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
    user = session.get('user')
    if not user:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 401

    convs = Conversation.query.filter_by(user_email=user).order_by(Conversation.id.desc()).all()
    out = []
    for c in convs:
        last_msg = None
        if c.messages:
            last_msg = c.messages[-1].message
        out.append({
            'id': c.id,
            'title': c.title,
            'created_at': c.created_at,
            'lastMessage': last_msg
        })
    return jsonify({'success': True, 'conversations': out})

@app.route('/api/conversations/<int:conv_id>/messages', methods=['GET'])
def get_messages(conv_id):
    user = session.get('user')
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
    user = session.get('user')
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
    user = session.get('user')
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