#!/usr/bin/env python3
"""
Extract and display composer data which likely contains chat conversations
"""

import json
import sqlite3
from datetime import datetime

def extract_composer_data():
    """Extract composer data from the database"""
    
    db_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918\state.vscdb"
    
    print("Extracting composer and chat data...")
    print()
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get specific keys that likely contain chat data
        important_keys = [
            'composer.composerData',
            'aiService.prompts',
            'aiService.generations',
            'interactive.sessions'
        ]
        
        extracted_data = {}
        
        for key in important_keys:
            cursor.execute("SELECT value FROM ItemTable WHERE key = ?", (key,))
            result = cursor.fetchone()
            
            if result:
                value = result[0]
                try:
                    if isinstance(value, bytes):
                        value_str = value.decode('utf-8', errors='ignore')
                    else:
                        value_str = str(value)
                    
                    value_json = json.loads(value_str)
                    extracted_data[key] = value_json
                    
                    print(f"Extracted: {key}")
                    if isinstance(value_json, dict):
                        print(f"  Keys: {list(value_json.keys())[:10]}")
                    elif isinstance(value_json, list):
                        print(f"  Length: {len(value_json)}")
                        if len(value_json) > 0 and isinstance(value_json[0], dict):
                            print(f"  First item keys: {list(value_json[0].keys())[:10]}")
                except Exception as e:
                    print(f"  Error parsing {key}: {e}")
                    extracted_data[key] = value_str[:1000] if len(value_str) > 1000 else value_str
            else:
                print(f"Not found: {key}")
        
        print()
        
        # Save extracted data
        output_file = "composer_chat_data.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump({
                'extracted_at': datetime.now().isoformat(),
                'data': extracted_data
            }, f, indent=2, default=str)
        
        print(f"Saved to: {output_file}")
        print()
        
        # Try to extract actual conversations from composer data
        if 'composer.composerData' in extracted_data:
            composer_data = extracted_data['composer.composerData']
            print("Analyzing composer data...")
            print()
            
            if isinstance(composer_data, dict) and 'allComposers' in composer_data:
                composers = composer_data['allComposers']
                print(f"Found {len(composers)} composers")
                print()
                
                for i, composer in enumerate(composers[:10]):  # Show first 10
                    print(f"Composer {i+1}:")
                    if isinstance(composer, dict):
                        for key, value in list(composer.items())[:15]:
                            if key in ['composerId', 'createdAt', 'type', 'unifiedMode', 'forceMode']:
                                print(f"  {key}: {value}")
                            elif key == 'totalLines' and isinstance(value, (int, float)):
                                print(f"  {key}: {value}")
                            elif isinstance(value, (dict, list)) and len(str(value)) < 200:
                                print(f"  {key}: {value}")
                    print()
        
        # Show prompts and generations
        if 'aiService.prompts' in extracted_data:
            prompts = extracted_data['aiService.prompts']
            if isinstance(prompts, list):
                print(f"\nFound {len(prompts)} prompts:")
                for i, prompt in enumerate(prompts[:5]):
                    if isinstance(prompt, dict) and 'text' in prompt:
                        print(f"  Prompt {i+1}: {prompt['text'][:200]}...")
        
        if 'aiService.generations' in extracted_data:
            generations = extracted_data['aiService.generations']
            if isinstance(generations, list):
                print(f"\nFound {len(generations)} generations:")
                for i, gen in enumerate(generations[:5]):
                    if isinstance(gen, dict):
                        print(f"  Generation {i+1}:")
                        for key in ['type', 'textDescription', 'unixMs']:
                            if key in gen:
                                print(f"    {key}: {gen[key]}")
        
        conn.close()
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("=" * 60)
    print("Composer Data Extractor")
    print("=" * 60)
    print()
    extract_composer_data()

