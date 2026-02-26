#!/usr/bin/env python3
"""
Find and display actual chat session data from extracted files
"""

import json
import os

def find_chat_sessions(json_file):
    """Find chat session data in the extracted JSON"""
    
    if not os.path.exists(json_file):
        print(f"File not found: {json_file}")
        return
    
    print(f"\n{'='*60}")
    print(f"Analyzing: {json_file}")
    print(f"{'='*60}\n")
    
    with open(json_file, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    chat_data = data.get('chat_data', {})
    
    # Look for keys that likely contain conversations
    important_keys = [
        'interactive.sessions',
        'composer.composerData',
        'aiService.generations',
        'aiService.prompts',
        'workbench.panel.aichat',
        'workbench.panel.composerChatViewPane'
    ]
    
    print("Looking for important chat keys...\n")
    
    found_sessions = []
    for key in important_keys:
        # Check for exact matches or partial matches
        matching_keys = [k for k in chat_data.keys() if key in k]
        if matching_keys:
            print(f"Found keys matching '{key}':")
            for match_key in matching_keys:
                print(f"  - {match_key}")
                value = chat_data[match_key]
                
                # Try to extract meaningful data
                if isinstance(value, dict):
                    if 'sessions' in value or 'conversations' in value or 'messages' in value:
                        found_sessions.append({
                            'key': match_key,
                            'type': 'structured',
                            'data': value
                        })
                        print(f"    -> Contains structured session data!")
                    else:
                        print(f"    -> Dict with keys: {list(value.keys())[:10]}")
                elif isinstance(value, list) and len(value) > 0:
                    print(f"    -> List with {len(value)} items")
                    if isinstance(value[0], dict):
                        print(f"    -> First item keys: {list(value[0].keys())[:10]}")
                        found_sessions.append({
                            'key': match_key,
                            'type': 'list',
                            'data': value
                        })
                elif isinstance(value, str) and len(value) > 100:
                    print(f"    -> Large string ({len(value)} chars)")
                    # Check if it contains JSON
                    if '{' in value or '[' in value:
                        try:
                            parsed = json.loads(value)
                            found_sessions.append({
                                'key': match_key,
                                'type': 'json_string',
                                'data': parsed
                            })
                            print(f"    -> Contains parseable JSON!")
                        except:
                            pass
            print()
    
    # Look for any key with "session" or "conversation" in the name
    print("\nSearching for all session/conversation related keys...\n")
    session_keys = [k for k in chat_data.keys() if 'session' in k.lower() or 'conversation' in k.lower() or 'message' in k.lower()]
    
    if session_keys:
        print(f"Found {len(session_keys)} session-related keys:")
        for key in session_keys[:20]:
            print(f"  - {key}")
            value = chat_data[key]
            if isinstance(value, (dict, list)):
                print(f"    -> {type(value).__name__}")
                if isinstance(value, dict) and len(value) > 0:
                    print(f"    -> Keys: {list(value.keys())[:5]}")
                elif isinstance(value, list) and len(value) > 0:
                    print(f"    -> Length: {len(value)}")
            elif isinstance(value, str):
                print(f"    -> String length: {len(value)}")
        print()
    
    # Save found sessions
    if found_sessions:
        output_file = json_file.replace('.json', '_sessions.json')
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump({
                'source_file': json_file,
                'found_sessions': found_sessions
            }, f, indent=2, default=str)
        print(f"\nSaved {len(found_sessions)} session records to: {output_file}")
    
    return found_sessions

if __name__ == "__main__":
    print("=" * 60)
    print("Chat Session Finder")
    print("=" * 60)
    
    # Analyze both files
    main_sessions = find_chat_sessions("extracted_chats_main.json")
    backup_sessions = find_chat_sessions("extracted_chats_backup.json")
    
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Main database: {len(main_sessions) if main_sessions else 0} sessions found")
    print(f"Backup database: {len(backup_sessions) if backup_sessions else 0} sessions found")
    print("\nCheck the *_sessions.json files for detailed session data.")

