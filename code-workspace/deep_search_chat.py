#!/usr/bin/env python3
"""
Deep search for chat data in workspace database
"""

import sqlite3
import json
import os
from datetime import datetime

def deep_search_workspace_db():
    """Deep search the workspace database for any chat data"""
    
    db_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918\state.vscdb"
    
    if not os.path.exists(db_path):
        print(f"Database not found: {db_path}")
        return
    
    print(f"Deep searching: {db_path}")
    print()
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get ALL items
        cursor.execute("SELECT key, value FROM ItemTable")
        all_items = cursor.fetchall()
        
        print(f"Total items in database: {len(all_items)}")
        print()
        
        # Look for ANY key that might contain chat data
        potential_chat_items = []
        
        for key, value in all_items:
            key_str = str(key)
            value_str = None
            
            try:
                if isinstance(value, bytes):
                    value_str = value.decode('utf-8', errors='ignore')
                else:
                    value_str = str(value)
            except:
                continue
            
            # Check if value contains chat-like content
            if value_str and len(value_str) > 50:
                value_lower = value_str.lower()
                
                # Look for indicators of chat content
                chat_indicators = [
                    'message', 'user', 'assistant', 'role', 'content', 
                    'conversation', 'chat', 'prompt', 'response',
                    'text', 'body', 'messages', 'thread'
                ]
                
                indicator_count = sum(1 for indicator in chat_indicators if indicator in value_lower)
                
                if indicator_count >= 2:  # At least 2 indicators
                    # Try to parse as JSON
                    try:
                        value_json = json.loads(value_str)
                        potential_chat_items.append({
                            'key': key_str,
                            'type': 'json',
                            'indicators': indicator_count,
                            'data': value_json,
                            'preview': str(value_json)[:500]
                        })
                    except:
                        # Not JSON, but might still be chat data
                        if len(value_str) > 200:
                            potential_chat_items.append({
                                'key': key_str,
                                'type': 'string',
                                'indicators': indicator_count,
                                'data': value_str[:2000],  # First 2000 chars
                                'preview': value_str[:500]
                            })
            elif value_str and any(term in key_str.lower() for term in ['chat', 'message', 'conversation', 'session']):
                # Key name suggests it's chat-related
                try:
                    value_json = json.loads(value_str)
                    potential_chat_items.append({
                        'key': key_str,
                        'type': 'json',
                        'indicators': 'key_match',
                        'data': value_json,
                        'preview': str(value_json)[:500]
                    })
                except:
                    potential_chat_items.append({
                        'key': key_str,
                        'type': 'string',
                        'indicators': 'key_match',
                        'data': value_str,
                        'preview': value_str[:500]
                    })
        
        print(f"Found {len(potential_chat_items)} items that might contain chat data")
        print()
        
        # Sort by indicator count (most likely first)
        potential_chat_items.sort(key=lambda x: x.get('indicators', 0) if isinstance(x.get('indicators'), int) else 0, reverse=True)
        
        # Show top candidates
        print("Top candidates for chat data:")
        print()
        for i, item in enumerate(potential_chat_items[:20]):
            print(f"{i+1}. Key: {item['key']}")
            print(f"   Type: {item['type']}, Indicators: {item['indicators']}")
            print(f"   Preview: {item['preview'][:200]}...")
            print()
        
        # Save all potential items
        output_file = "deep_search_results.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump({
                'database_path': db_path,
                'extracted_at': datetime.now().isoformat(),
                'total_items_searched': len(all_items),
                'potential_chat_items': potential_chat_items
            }, f, indent=2, default=str)
        
        print(f"\nSaved all results to: {output_file}")
        
        conn.close()
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("=" * 60)
    print("Deep Chat Search")
    print("=" * 60)
    print()
    deep_search_workspace_db()

