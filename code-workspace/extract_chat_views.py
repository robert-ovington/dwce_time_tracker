#!/usr/bin/env python3
"""
Extract chat data from workbench.panel.aichat.view.* keys
"""

import json
import os
import re

def extract_chat_views(json_file):
    """Extract data from chat view keys"""
    
    if not os.path.exists(json_file):
        print(f"File not found: {json_file}")
        return
    
    print(f"\n{'='*60}")
    print(f"Extracting chat views from: {json_file}")
    print(f"{'='*60}\n")
    
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    chat_data = data.get('chat_data', {})
    
    # Find all keys that match workbench.panel.aichat.view.*
    view_keys = [k for k in chat_data.keys() if 'workbench.panel.aichat.view.' in k]
    
    print(f"Found {len(view_keys)} chat view keys\n")
    
    conversations = []
    
    for key in view_keys:
        value = chat_data[key]
        print(f"Key: {key}")
        
        if isinstance(value, dict):
            print(f"  Type: Dict")
            print(f"  Keys: {list(value.keys())[:10]}")
            
            # Look for conversation-like data
            if 'messages' in value or 'conversation' in str(value).lower():
                conversations.append({
                    'key': key,
                    'type': 'dict_with_messages',
                    'data': value
                })
                print(f"  *** Contains messages/conversation data! ***")
            
            # Check nested structures
            for subkey, subvalue in list(value.items())[:5]:
                if isinstance(subvalue, (dict, list)):
                    print(f"  {subkey}: {type(subvalue).__name__} (length: {len(subvalue) if isinstance(subvalue, list) else 'N/A'})")
                elif isinstance(subvalue, str):
                    print(f"  {subkey}: string (length: {len(subvalue)})")
                    if len(subvalue) > 100 and ('message' in subvalue.lower() or 'user' in subvalue.lower() or 'assistant' in subvalue.lower()):
                        print(f"    *** Might contain chat content! ***")
                        try:
                            parsed = json.loads(subvalue)
                            conversations.append({
                                'key': f"{key}.{subkey}",
                                'type': 'json_string',
                                'data': parsed
                            })
                        except:
                            pass
        elif isinstance(value, list):
            print(f"  Type: List (length: {len(value)})")
            if len(value) > 0:
                print(f"  First item type: {type(value[0]).__name__}")
                if isinstance(value[0], dict):
                    print(f"  First item keys: {list(value[0].keys())[:10]}")
                    # Check if it looks like messages
                    if any(k in str(value[0]).lower() for k in ['message', 'content', 'text', 'role', 'user', 'assistant']):
                        conversations.append({
                            'key': key,
                            'type': 'list_of_messages',
                            'data': value
                        })
                        print(f"  *** Looks like a list of messages! ***")
        elif isinstance(value, str):
            print(f"  Type: String (length: {len(value)})")
            if len(value) > 100:
                # Try to parse as JSON
                try:
                    parsed = json.loads(value)
                    conversations.append({
                        'key': key,
                        'type': 'json_string',
                        'data': parsed
                    })
                    print(f"  *** Contains parseable JSON! ***")
                except:
                    # Check if it contains chat-like content
                    if any(term in value.lower() for term in ['message', 'user', 'assistant', 'conversation', 'chat']):
                        print(f"  *** Might contain chat content (first 200 chars): {value[:200]}... ***")
        print()
    
    # Save conversations
    if conversations:
        output_file = json_file.replace('.json', '_conversations.json')
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump({
                'source_file': json_file,
                'conversations': conversations,
                'total_found': len(conversations)
            }, f, indent=2, default=str)
        print(f"\nSaved {len(conversations)} conversation records to: {output_file}")
    else:
        print("\nNo conversation data found in view keys.")
    
    return conversations

if __name__ == "__main__":
    print("=" * 60)
    print("Chat View Extractor")
    print("=" * 60)
    
    main_convos = extract_chat_views("extracted_chats_main.json")
    backup_convos = extract_chat_views("extracted_chats_backup.json")
    
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Main database: {len(main_convos) if main_convos else 0} conversations found")
    print(f"Backup database: {len(backup_convos) if backup_convos else 0} conversations found")

