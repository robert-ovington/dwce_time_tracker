#!/usr/bin/env python3
"""
Check globalStorage for chat history
"""

import sqlite3
import json
import os
from datetime import datetime

def check_global_storage():
    """Check globalStorage database for chat data"""
    
    db_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\globalStorage\state.vscdb"
    
    if not os.path.exists(db_path):
        print(f"Global storage database not found: {db_path}")
        return
    
    print(f"Checking global storage: {db_path}")
    print(f"Last modified: {datetime.fromtimestamp(os.path.getmtime(db_path))}")
    print()
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]
        print(f"Tables: {', '.join(tables)}")
        print()
        
        if 'ItemTable' in tables:
            # Get all items
            cursor.execute("SELECT key, value FROM ItemTable")
            all_items = cursor.fetchall()
            print(f"Total items: {len(all_items)}")
            print()
            
            # Look for chat-related keys
            chat_keys = []
            for key, value in all_items:
                key_str = str(key)
                if any(term in key_str.lower() for term in ['chat', 'conversation', 'message', 'aichat', 'interactive', 'composer']):
                    chat_keys.append((key_str, value))
            
            print(f"Found {len(chat_keys)} chat-related items:")
            print()
            
            chat_data = {}
            for key, value in chat_keys[:30]:  # Show first 30
                print(f"Key: {key}")
                try:
                    if isinstance(value, bytes):
                        value_str = value.decode('utf-8', errors='ignore')
                    else:
                        value_str = str(value)
                    
                    if len(value_str) > 500:
                        print(f"  Value: {value_str[:200]}... (truncated, total: {len(value_str)} chars)")
                    else:
                        print(f"  Value: {value_str}")
                    
                    # Try to parse as JSON
                    try:
                        value_json = json.loads(value_str)
                        chat_data[key] = value_json
                        print(f"  -> Parseable JSON")
                        if isinstance(value_json, dict):
                            print(f"  -> Dict keys: {list(value_json.keys())[:10]}")
                        elif isinstance(value_json, list):
                            print(f"  -> List length: {len(value_json)}")
                    except:
                        pass
                except Exception as e:
                    print(f"  Error processing: {e}")
                print()
            
            # Save findings
            if chat_data:
                output_file = "global_storage_chats.json"
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump({
                        'database_path': db_path,
                        'extracted_at': datetime.now().isoformat(),
                        'chat_data': chat_data
                    }, f, indent=2, default=str)
                print(f"\nSaved chat data to: {output_file}")
        
        conn.close()
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("=" * 60)
    print("Global Storage Chat Checker")
    print("=" * 60)
    print()
    check_global_storage()

