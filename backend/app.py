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
import re
from itsdangerous import URLSafeTimedSerializer


app = Flask(__name__)

app.config['SECRET_KEY'] = 'arogyamitra_secret_key'  # change later for production
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///users.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
CORS(app)

db = SQLAlchemy(app)

serializer = URLSafeTimedSerializer(app.config['SECRET_KEY'])

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    age = db.Column(db.Integer, nullable=True)
    gender = db.Column(db.String(20), nullable=True)

    is_verified = db.Column(db.Boolean, default=False)
    verification_token = db.Column(db.String(255), nullable=True)

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
                max_depth=15, # Increased depth to handle specific single-symptom patterns
                min_samples_split=2,
                min_samples_leaf=1
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

    def clean_and_extract_symptoms(self, input_text, threshold=90):
        detected_symptoms = []
        text = input_text.strip().lower()

        # Step 0: Direct Master List Match (handles UI checkbox returns)
        for s in self.symptoms_list:
            if s.lower() in text:
                detected_symptoms.append(s)

        # Step 1: Match from phrase dictionary
        for symptom, phrases in SYMPTOM_PHRASES_MARATHI.items():
            if symptom in detected_symptoms:
                continue
            for phrase in phrases:
                if phrase.lower() in text:
                    detected_symptoms.append(symptom)
                    break

        # Step 2: Fuzzy match for remaining if nothing detected yet
        if not detected_symptoms:
            for symptom, phrases in SYMPTOM_PHRASES_MARATHI.items():
                for phrase in phrases:
                    if fuzz.token_set_ratio(text, phrase.lower()) >= threshold:
                        detected_symptoms.append(symptom)
                        break

        return list(set(detected_symptoms))

    def get_followup_symptoms(self, detected_symptoms, top_n=6):
        try:
            if not detected_symptoms:
                return self.symptoms_list[:top_n]

            matching_df = self.df.copy()
            for symptom in detected_symptoms:
                if symptom in matching_df.columns:
                    matching_df = matching_df[matching_df[symptom] == 1]

            if matching_df.empty:
                common_symptoms = self.df.sum().sort_values(ascending=False).index.tolist()
                followup = [s for s in common_symptoms if s not in detected_symptoms]
                return followup[:top_n]

            symptom_counts = {}
            for symptom in self.symptoms_list:
                if symptom in detected_symptoms: continue
                count = matching_df[symptom].sum()
                if count > 0:
                    symptom_counts[symptom] = int(count)

            sorted_symptoms = sorted(symptom_counts.items(), key=lambda x: x[1], reverse=True)
            followup = [symptom for symptom, count in sorted_symptoms[:top_n]]

            if not followup:
                followup = [s for s in self.symptoms_list if s not in detected_symptoms]
                return followup[:top_n]

            return followup
        except Exception as e:
            print(f"Error generating follow-up symptoms: {e}")
            return self.symptoms_list[:top_n]

    def predict_disease(self, symptoms):
        try:
            if not symptoms or not self.rf_model or not self.label_encoder:
                return None, 0.0, symptoms

            input_vector = [1 if s in symptoms else 0 for s in self.symptoms_list]
            input_df = pd.DataFrame([input_vector], columns=self.symptoms_list)

            probs_rf = self.rf_model.predict_proba(input_df)[0]

            top_indices = probs_rf.argsort()[-3:][::-1]

            top_predictions = []

            for idx in top_indices:

                disease_name = self.label_encoder.classes_[idx]

                top_predictions.append({
                    "disease": disease_name,
                    "probability": round(float(probs_rf[idx]), 2)
                })

            top1 = top_predictions[0]["probability"]
            top2 = top_predictions[1]["probability"]

            is_ambiguous = abs(top1 - top2) < 0.15

            return top_predictions, is_ambiguous, symptoms

        except Exception as e:
            print(f"✗ Error during prediction: {e}")
            return None, 0.0, symptoms


# Initialize predictor
predictor = DiseasePredictor()

def get_current_user():
    user = session.get('user')
    if user: return user
    email = request.args.get('email')
    if email: return email
    if request.is_json:
        try:
            data = request.get_json(silent=True)
            if data and 'email' in data: return data.get('email')
        except: pass
    return None

@app.route('/api/signup', methods=['POST'])
def signup():
    data = request.get_json()
    name, email, password = data.get('name'), data.get('email'), data.get('password')
    if not (name and email and password):
        return jsonify({"success": False, "message": "सर्व FIELD भरा"}), 400
    if User.query.filter_by(email=email).first():
        return jsonify({"success": False, "message": "ईमेल आधीच नोंदणीकृत आहे"}), 409
    token = serializer.dumps(email, salt='email-verification')

    new_user = User(
        name=name,
        email=email,
        password_hash=generate_password_hash(password),
        age=data.get('age'),
        gender=data.get('gender'),
        verification_token=token,
        is_verified=False
    )

    db.session.add(new_user)
    db.session.commit()

    return jsonify({
        "success": True,
        "message": "नोंदणी यशस्वी! कृपया तुमचा ईमेल तपासा.",
        "verification_token": token
    }), 201

@app.route('/api/verify-email/<token>', methods=['GET'])
def verify_email(token):
    try:
        email = serializer.loads(
            token,
            salt='email-verification',
            max_age=3600
        )

        user = User.query.filter_by(email=email).first()

        if not user:
            return jsonify({
                "success": False,
                "message": "User not found"
            }), 404

        user.is_verified = True
        user.verification_token = None

        db.session.commit()

        return """
        <h2>तुमचा ईमेल यशस्वीरित्या सत्यापित झाला!</h2>
        <p>आता तुम्ही AarogyaMitra मध्ये लॉगिन करू शकता.</p>
        """

    except Exception as e:
        print(e)

        return jsonify({
            "success": False,
            "message": "Invalid or expired token"
        }), 400


@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(email=data.get('email')).first()
    if not user or not check_password_hash(user.password_hash, data.get('password')):
        return jsonify({"success": False, "message": "चुकीचे ईमेल किंवा पासवर्ड"}), 401

    if not user.is_verified:
        return jsonify({
            "success": False,
            "message": "कृपया प्रथम तुमचा ईमेल सत्यापित करा."
        }), 403

    session['user'] = user.email
    return jsonify({"success": True, "message": "लॉगिन यशस्वी"}), 200

@app.route('/api/logout', methods=['POST'])
def logout():
    session.pop('user', None)
    return jsonify({"success": True, "message": "लॉगआउट यशस्वी"}), 200

@app.route('/api/profile', methods=['GET'])
def get_profile():
    email = get_current_user()
    if not email: return jsonify({'success': False, 'message': 'Unauthorized'}), 401
    user = User.query.filter_by(email=email).first()
    if not user: return jsonify({'success': False, 'message': 'User not found'}), 404
    return jsonify({'success': True, 'name': user.name, 'email': user.email, 'age': user.age, 'gender': user.gender})

@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

@app.route('/api/symptoms', methods=['GET'])
def get_symptoms():
    return jsonify({'symptoms': predictor.symptoms_list, 'count': len(predictor.symptoms_list), 'language': 'marathi'})

@app.route('/api/diseases', methods=['GET'])
def get_diseases():
    diseases = predictor.label_encoder.classes_.tolist() if predictor.label_encoder else []
    return jsonify({'diseases': diseases, 'count': len(diseases), 'language': 'marathi'})


@app.route('/api/predict', methods=['POST'])
def predict_disease_api():
    try:
        data = request.json
        text, no_more_symptoms, conversation_id = data.get('text', ''), data.get('no_more_symptoms', False), data.get('conversation_id')
        if not text: return jsonify({'success': False, 'error': 'No text provided'})

        print(f"📥 Prediction Request: '{text}' (no_more={no_more_symptoms})")

        # Basic gibberish/emoji check
        if not re.search(r'[a-zA-Z\u0900-\u097F]', text):
            return jsonify({'success': False, 'error_marathi': "कृपया चिन्हे किंवा इमोजीऐवजी तुमची लक्षणे शब्दांत सांगा.", 'suggested_symptoms': predictor.symptoms_list[:10]})

        symptoms = predictor.clean_and_extract_symptoms(text)
        if not symptoms:
            return jsonify({'success': False, 'error_marathi': "माफ करा, लक्षणे सापडली नाहीत. कृपया तुमची लक्षणे स्पष्टपणे सांगा.", 'suggested_symptoms': predictor.symptoms_list[:10]})

        top_predictions, is_ambiguous, _ = predictor.predict_disease(symptoms)

        best_prediction = top_predictions[0]

        disease = best_prediction["disease"]
        probability = best_prediction["probability"]

        # Simple vs Complex logic
        SIMPLE_DISEASES = ["सर्दी-खोकला", "मुरुम", "ॲसिड रिफ्लक्स", "ॲलर्जी", "फंगल इन्फेक्शन", "पोटदुखी", "खाज", "ताप"]
        threshold = 0.30 if disease in SIMPLE_DISEASES else 0.55

        if len(symptoms) <= 2 and not no_more_symptoms and probability < threshold:
            return jsonify({
                'success': True,
                'follow_up_needed': True,
                'detected_symptoms': symptoms,
                'suggested_symptoms': predictor.get_followup_symptoms(symptoms),
                'message': 'कृपया आणखी लक्षणे निवडा'
            })

        if no_more_symptoms:
            is_ambiguous = False

        # If user says "None of the above",
        # proceed with best possible prediction
        if len(symptoms) <= 2 and no_more_symptoms:
            print("⚠️ वापरकर्त्याने 'वरीलपैकी काहीही नाही' निवडले. उपलब्ध लक्षणांवर आधारित अंदाज देत आहोत.")

        if conversation_id:
            conv = db.session.get(Conversation, int(conversation_id))
            if conv: conv.title = disease; db.session.commit()

        raw_prec = predictor.disease_precautions.get(disease, ["डॉक्टरांचा सल्ला घ्या."])
        precautions_list = []
        if isinstance(raw_prec, dict):
            for v in raw_prec.values():
                if isinstance(v, list): precautions_list.extend(v)
                elif isinstance(v, str): precautions_list.append(v)
        elif isinstance(raw_prec, list): precautions_list = list(raw_prec)
        else: precautions_list = [str(raw_prec)]

        precautions_list = list(dict.fromkeys([p.strip() for p in precautions_list if p]))

        for prediction in top_predictions:

            disease_name = prediction["disease"]

            raw_precautions = predictor.disease_precautions.get(
                disease_name,
                ["डॉक्टरांचा सल्ला घ्या."]
            )

            parsed_precautions = []

            if isinstance(raw_precautions, dict):

                for value in raw_precautions.values():

                    if isinstance(value, list):
                        parsed_precautions.extend(value)

                    elif isinstance(value, str):
                        parsed_precautions.append(value)

            elif isinstance(raw_precautions, list):

                parsed_precautions = list(raw_precautions)

            else:

                parsed_precautions = [str(raw_precautions)]

            parsed_precautions = list(
                dict.fromkeys([
                    p.strip()
                    for p in parsed_precautions
                    if p
                ])
            )

            prediction["precautions"] = parsed_precautions

        confidence_level = "उच्च" if probability > 0.7 else "मध्यम" if probability > 0.4 else "कमी"

        extra_message = ""

        if len(symptoms) <= 2 and no_more_symptoms:
            extra_message = "दिलेल्या मर्यादित लक्षणांवर आधारित अंदाज देण्यात आला आहे."


        return jsonify({
             'success': True,
             'symptoms_detected': symptoms,
             'disease_marathi': disease,
             'probability': probability,
             'confidence': confidence_level,
             'precautions_marathi': precautions_list,
             'ambiguous': is_ambiguous,
             'top_predictions': top_predictions,
             'message': f'तुमच्या लक्षणांवरून, तुम्हाला {disease} असू शकते. {extra_message}'
        })



    except Exception as e:
        print(f"💥 Error: {e}"); return jsonify({'success': False, 'error': str(e)})

@app.route('/api/speech-to-text', methods=['POST'])
def speech_to_text():
    try:
        import tempfile
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as tmp:
            tmp.write(request.data); tmp_path = tmp.name
        r = sr.Recognizer()
        with sr.AudioFile(tmp_path) as src:
            audio = r.record(src)
            try:
                text = r.recognize_google(audio, language='mr-IN')
                res = {'success': True, 'text': text}
            except: res = {'success': False, 'error': 'समजू शकले नाही.'}
        try: os.unlink(tmp_path)
        except: pass
        return jsonify(res)
    except Exception as e: return jsonify({'success': False, 'error': str(e)})

@app.route('/api/conversations', methods=['POST', 'GET'])
def manage_conversations():
    email = get_current_user()
    if not email: return jsonify({'success': False}), 401
    if request.method == 'POST':
        data = request.get_json() or {}
        title = data.get('title') or f'संभाषण {datetime.utcnow().isoformat()}'
        conv = Conversation(title=title, user_email=email)
        db.session.add(conv); db.session.commit()
        return jsonify({'success': True, 'id': conv.id, 'title': conv.title}), 201
    convs = Conversation.query.filter_by(user_email=email).order_by(Conversation.id.desc()).all()
    return jsonify({'success': True, 'conversations': [{'id':c.id, 'title':c.title, 'created_at':c.created_at} for c in convs]})

@app.route('/api/conversations/<int:conv_id>', methods=['DELETE'])
def delete_conversation(conv_id):
    email = get_current_user()
    conv = Conversation.query.filter_by(id=conv_id, user_email=email).first()
    if not conv: return jsonify({'success': False}), 404
    db.session.delete(conv); db.session.commit()
    return jsonify({'success': True})

@app.route('/api/conversations/<int:conv_id>/messages', methods=['GET', 'POST'])
def manage_messages(conv_id):
    email = get_current_user()
    conv = Conversation.query.filter_by(id=conv_id, user_email=email).first()
    if not conv: return jsonify({'success': False}), 404
    if request.method == 'POST':
        data = request.json
        m = Message(conversation_id=conv.id, message=data.get('message'), is_user=data.get('is_user', False), disease=data.get('disease'), precautions=json.dumps(data.get('precautions')), symptoms=json.dumps(data.get('symptoms')))
        db.session.add(m); db.session.commit()
        return jsonify({'success': True, 'id': m.id}), 201
    return jsonify({'success': True, 'messages': [{'message':m.message, 'is_user':m.is_user, 'disease':m.disease, 'precautions': json.loads(m.precautions) if m.precautions else None, 'symptoms':json.loads(m.symptoms or '[]'), 'timestamp': m.timestamp} for m in conv.messages]})

def create_tables():
    with app.app_context(): db.create_all()

if __name__ == '__main__':
    os.makedirs('model', exist_ok=True); os.makedirs('data', exist_ok=True); create_tables()
    app.run(debug=True, host='0.0.0.0', port=5000, use_reloader=False)
