#!/usr/bin/env python3
"""
Extract actual chat conversations from Cursor's state.vscdb
"""

import sqlite3
import json
import os
from pathlib import Path
from datetime import datetime

def extract_all_chat_data(db_path, output_file="extracted_chats.json"):
    """Extract all chat-related data from the database"""
    
    if not os.path.exists(db_path):
        print(f"ERROR: Database file not found: {db_path}")
        return None
    
    print(f"Extracting chat data from: {db_path}")
    print()
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get all items from ItemTable
        cursor.execute("SELECT key, value FROM ItemTable")
        all_items = cursor.fetchall()
        
        print(f"Found {len(all_items)} total items in ItemTable")
        
        chat_data = {}
        chat_keys = []
        
        # Look for chat-related keys
        for key, value in all_items:
            key_str = str(key)
            
            # Check if this is chat-related
            if any(term in key_str.lower() for term in ['chat', 'conversation', 'message', 'aichat', 'cursor']):
                try:
                    # Try to decode value
                    if isinstance(value, bytes):
                        value_str = value.decode('utf-8', errors='ignore')
                    else:
                        value_str = str(value)
                    
                    # Try to parse as JSON
                    try:
                        value_json = json.loads(value_str)
                        chat_data[key_str] = value_json
                        chat_keys.append(key_str)
                    except:
                        # If not JSON, store as string (truncated if too long)
                        if len(value_str) > 1000:
                            chat_data[key_str] = value_str[:1000] + "... (truncated)"
                        else:
                            chat_data[key_str] = value_str
                        chat_keys.append(key_str)
                except Exception as e:
                    pass
        
        print(f"Extracted {len(chat_keys)} chat-related items")
        print()
        
        # Show some key names
        print("Sample keys found:")
        for key in chat_keys[:20]:
            print(f"  - {key}")
        if len(chat_keys) > 20:
            print(f"  ... and {len(chat_keys) - 20} more")
        print()
        
        # Look specifically for conversation/chat data
        conversations = []
        for key, value in all_items:
            key_str = str(key)
            
            # Look for keys that might contain actual conversation data
            if any(term in key_str.lower() for term in ['conversation', 'chat.history', 'messages', 'thread']):
                try:
                    if isinstance(value, bytes):
                        value_str = value.decode('utf-8', errors='ignore')
                    else:
                        value_str = str(value)
                    
                    try:
                        value_json = json.loads(value_str)
                        # Check if this looks like conversation data
                        if isinstance(value_json, (dict, list)):
                            conversations.append({
                                'key': key_str,
                                'data': value_json
                            })
                    except:
                        # Check if it's a string that might contain JSON
                        if '{' in value_str or '[' in value_str:
                            try:
                                # Try to find JSON in the string
                                start = value_str.find('{')
                                if start == -1:
                                    start = value_str.find('[')
                                if start != -1:
                                    end = value_str.rfind('}') + 1
                                    if end == 0:
                                        end = value_str.rfind(']') + 1
                                    if end > start:
                                        json_str = value_str[start:end]
                                        value_json = json.loads(json_str)
                                        conversations.append({
                                            'key': key_str,
                                            'data': value_json
                                        })
                            except:
                                pass
                except Exception as e:
                    pass
        
        if conversations:
            print(f"Found {len(conversations)} potential conversation records!")
            print()
        
        conn.close()
        
        # Save everything
        output = {
            'database_path': db_path,
            'extracted_at': datetime.now().isoformat(),
            'total_items': len(all_items),
            'chat_keys': chat_keys,
            'chat_data': chat_data,
            'conversations': conversations
        }
        
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(output, f, indent=2, default=str)
        
        print(f"All data saved to: {output_file}")
        return output
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    print("=" * 60)
    print("Cursor Chat Conversation Extractor")
    print("=" * 60)
    print()
    
    # Try main database
    db_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918\state.vscdb"
    backup_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918\state.vscdb.backup"
    
    print("Extracting from main database...")
    main_data = extract_all_chat_data(db_path, "extracted_chats_main.json")
    print()
    
    print("Extracting from backup database...")
    backup_data = extract_all_chat_data(backup_path, "extracted_chats_backup.json")
    print()
    
    print("=" * 60)
    print("Extraction complete!")
    print("=" * 60)
    print()
    print("Next steps:")
    print("1. Check the extracted_chats_main.json and extracted_chats_backup.json files")
    print("2. Look for 'conversations' or 'chat_data' sections")
    print("3. The chat history should be in one of those JSON structures")

