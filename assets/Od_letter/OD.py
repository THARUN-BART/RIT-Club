import datetime
import json
import os
import tempfile

import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask, request, jsonify
from fpdf import FPDF
from supabase import create_client

app = Flask(__name__)

# Initialize Firebase for Firestore only
cred = credentials.Certificate('rit-club-firebase-adminsdk-fbsvc-623d2ff459.json')
firebase_admin.initialize_app(cred)

db = firestore.client()

# Initialize Supabase for Storage
supabase_url = "https://yxtcsazncerqtozowglr.supabase.co"
supabase_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl4dGNzYXpuY2VycXRvem93Z2xyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0NTk2Mjk2NywiZXhwIjoyMDYxNTM4OTY3fQ.ziXFUM0e2RKB5mKNvWm-iHyKd7L_gC35QTVRUTUjWpg"  # Replace with your service role key
supabase = create_client(supabase_url, supabase_key)

class PDF(FPDF):
    def header(self):
        # Add logo
        # self.image('logo.png', 10, 8, 33)
        # Add title
        self.set_font('Arial', 'B', 16)
        self.cell(0, 10, 'Event Participation Letter', 0, 1, 'C')
        # Line break
        self.ln(20)

    def footer(self):
        # Position at 1.5 cm from bottom
        self.set_y(-15)
        # Arial italic 8
        self.set_font('Arial', 'I', 8)
        # Page number
        self.cell(0, 10, f'Page {self.page_no()}/{{nb}}', 0, 0, 'C')

@app.route('/generate-letter', methods=['POST'])
def generate_letter():
    try:
        data = request.get_json()

        # Required fields
        user_id = data.get('userId')
        user_name = data.get('userName')
        event_id = data.get('eventId')
        event_name = data.get('eventName')
        event_date = data.get('eventDate')  # Format: "YYYY-MM-DD"

        if not all([user_id, user_name, event_id, event_name, event_date]):
            return jsonify({'error': 'Missing required fields'}), 400

        # Create PDF
        pdf = PDF()
        pdf.alias_nb_pages()
        pdf.add_page()

        # Set font
        pdf.set_font('Arial', '', 12)

        # Date
        today = datetime.datetime.now().strftime("%d %B %Y")
        pdf.cell(0, 10, f'Date: {today}', 0, 1)
        pdf.ln(10)

        # Greeting
        pdf.cell(0, 10, f'Dear {user_name},', 0, 1)
        pdf.ln(5)

        # Body
        pdf.multi_cell(0, 10, 'This letter confirms your registration for the following event:')
        pdf.ln(5)

        # Event details
        pdf.set_fill_color(240, 240, 240)
        pdf.cell(0, 10, f'Event Name: {event_name}', 1, 1, 'L', True)

        # Parse the date
        event_date_obj = datetime.datetime.strptime(event_date, "%Y-%m-%d")
        formatted_date = event_date_obj.strftime("%d %B %Y")
        pdf.cell(0, 10, f'Event Date: {formatted_date}', 1, 1, 'L', True)
        pdf.cell(0, 10, f'Participant: {user_name}', 1, 1, 'L', True)
        pdf.ln(10)

        # Footer text
        pdf.multi_cell(0, 10, 'Please keep this letter as confirmation of your registration. We look forward to your participation.')
        pdf.ln(10)
        pdf.cell(0, 10, 'Sincerely,', 0, 1)
        pdf.ln(5)
        pdf.cell(0, 10, 'Event Organizers', 0, 1)

        # Save the PDF to a temporary file
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as temp:
            temp_path = temp.name

        pdf.output(temp_path)

        # Upload to Supabase Storage
        file_name = f"event_letters/{user_id}/{event_id}/{event_name.replace(' ', '_')}_letter.pdf"

        # Read the file content
        with open(temp_path, 'rb') as pdf_file:
            file_content = pdf_file.read()

        # Upload to Supabase
        upload_response = supabase.storage.from_('event-letters').upload(
            file_name,
            file_content,
            {"content-type": "application/pdf"}
        )

        # Make the file publicly accessible (if needed)
        # Get the public URL
        public_url = supabase.storage.from_('event-letters').get_public_url(file_name)

        # Save letter info to Firestore
        letter_ref = db.collection('users').document(user_id).collection('eventLetters').document(event_id)
        letter_ref.set({
            'eventId': event_id,
            'eventName': event_name,
            'eventDate': firestore.SERVER_TIMESTAMP,
            'generatedDate': firestore.SERVER_TIMESTAMP,
            'letterUrl': public_url
        })

        # Clean up temporary file
        os.unlink(temp_path)

        return jsonify({
            'success': True,
            'letterUrl': public_url,
            'message': 'Letter generated successfully'
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/check-registration-ended', methods=['GET'])
def check_registration_ended():
    try:
        # Get all active events with registration end dates
        events_ref = db.collection('events')
        query = events_ref.where('status', '==', 'active').where('registrationEndDate', '<=', datetime.datetime.now())
        events = query.stream()

        for event in events:
            event_data = event.to_dict()
            event_id = event.id

            # Get all users who participated in this event
            users_ref = db.collection('users')
            users = users_ref.where('participatedEventIds', 'array_contains', event_id).stream()

            for user in users:
                user_id = user.id
                user_data = user.to_dict()
                user_name = user_data.get('name', 'User')

                # Check if letter already exists
                letter_ref = db.collection('users').document(user_id).collection('eventLetters').document(event_id)
                letter = letter_ref.get()

                if not letter.exists:
                    # Generate letter via API call to this service
                    event_date = event_data['eventDateTime'].strftime("%Y-%m-%d")

                    letter_data = {
                        'userId': user_id,
                        'userName': user_name,
                        'eventId': event_id,
                        'eventName': event_data.get('title', 'Event'),
                        'eventDate': event_date
                    }

                    # Call our own API to generate the letter
                    # In production, use requests library
                    generate_letter_response = app.test_client().post(
                        '/generate-letter',
                        data=json.dumps(letter_data),
                        content_type='application/json'
                    )

                    print(f"Generated letter for user {user_id}, event {event_id}")

        return jsonify({'success': True, 'message': 'Registration check completed'})

    except Exception as e:
        return jsonify({'error': str(e)}), 500

# Helper route to create the Supabase bucket if it doesn't exist
@app.route('/create-bucket', methods=['GET'])
def create_bucket():
    try:
        # Check if bucket exists, create if it doesn't
        buckets = supabase.storage.list_buckets()
        bucket_exists = any(bucket['name'] == 'event-letters' for bucket in buckets)

        if not bucket_exists:
            supabase.storage.create_bucket('event-letters', {'public': True})
            return jsonify({'success': True, 'message': 'Bucket created successfully'})
        else:
            return jsonify({'success': True, 'message': 'Bucket already exists'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=8080)