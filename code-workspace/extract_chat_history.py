#!/usr/bin/env python3
"""
Extract Cursor chat history from state.vscdb SQLite database
"""

import sqlite3
import json
import os
from pathlib import Path
from datetime import datetime

def extract_chat_history(db_path, output_file=None):
    """Extract chat history from Cursor's state.vscdb file"""
    
    if not os.path.exists(db_path):
        print(f"ERROR: Database file not found: {db_path}")
        return
    
    print(f"Opening database: {db_path}")
    print(f"Database last modified: {datetime.fromtimestamp(os.path.getmtime(db_path))}")
    print()
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get all table names
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = [row[0] for row in cursor.fetchall()]
        print(f"Found {len(tables)} tables:")
        for table in tables:
            print(f"   - {table}")
        print()
        
        # Look for chat-related tables
        chat_tables = [t for t in tables if 'chat' in t.lower() or 'conversation' in t.lower() or 'message' in t.lower()]
        kv_tables = [t for t in tables if 'kv' in t.lower() or 'keyvalue' in t.lower() or 'disk' in t.lower()]
        
        print("Searching for chat data...")
        print()
        
        # Check cursorDiskKV table (common location for Cursor data)
        if 'ItemTable' in tables:
            print("Checking ItemTable (common storage location)...")
            try:
                cursor.execute("SELECT key, value FROM ItemTable LIMIT 100")
                rows = cursor.fetchall()
                print(f"   Found {len(rows)} items in ItemTable")
                
                chat_items = []
                for key, value in rows:
                    key_str = str(key)
                    if any(term in key_str.lower() for term in ['chat', 'conversation', 'message', 'cursor']):
                        try:
                            if isinstance(value, bytes):
                                value_str = value.decode('utf-8', errors='ignore')
                            else:
                                value_str = str(value)
                            
                            # Try to parse as JSON
                            try:
                                value_json = json.loads(value_str)
                                chat_items.append({'key': key_str, 'value': value_json})
                            except:
                                chat_items.append({'key': key_str, 'value': value_str[:500]})  # First 500 chars
                        except Exception as e:
                            pass
                
                if chat_items:
                    print(f"   FOUND {len(chat_items)} potential chat-related items!")
                    for item in chat_items[:10]:  # Show first 10
                        print(f"      Key: {item['key'][:80]}...")
                else:
                    print("   No obvious chat items found in ItemTable")
                print()
            except Exception as e:
                print(f"   WARNING: Error reading ItemTable: {e}")
                print()
        
        # Check all tables for chat data
        all_chat_data = []
        for table in tables:
            try:
                # Get column names
                cursor.execute(f"PRAGMA table_info({table})")
                columns = [row[1] for row in cursor.fetchall()]
                
                # Check if table might contain chat data
                if any(col.lower() in ['key', 'value', 'data', 'content', 'message', 'text'] for col in columns):
                    cursor.execute(f"SELECT COUNT(*) FROM {table}")
                    count = cursor.fetchone()[0]
                    
                    if count > 0:
                        print(f"Table: {table} ({count} rows)")
                        print(f"   Columns: {', '.join(columns)}")
                        
                        # Try to read a sample
                        try:
                            cursor.execute(f"SELECT * FROM {table} LIMIT 5")
                            sample_rows = cursor.fetchall()
                            for i, row in enumerate(sample_rows):
                                row_dict = dict(zip(columns, row))
                                # Check if this looks like chat data
                                row_str = str(row_dict).lower()
                                if any(term in row_str for term in ['chat', 'conversation', 'message', 'user', 'assistant']):
                                    all_chat_data.append({
                                        'table': table,
                                        'data': row_dict
                                    })
                                    print(f"   *** Row {i+1} looks like chat data! ***")
                        except Exception as e:
                            pass
                        print()
            except Exception as e:
                pass
        
        # Try to find cursorDiskKV or similar
        for table in kv_tables:
            print(f"Checking {table}...")
            try:
                cursor.execute(f"SELECT * FROM {table} LIMIT 20")
                rows = cursor.fetchall()
                print(f"   Found {len(rows)} rows")
                
                # Show sample
                for i, row in enumerate(rows[:5]):
                    print(f"   Row {i+1}: {str(row)[:200]}...")
                print()
            except Exception as e:
                print(f"   WARNING: Error: {e}")
                print()
        
        # Save findings
        if output_file:
            output = {
                'database_path': db_path,
                'tables': tables,
                'chat_items': all_chat_data,
                'extracted_at': datetime.now().isoformat()
            }
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(output, f, indent=2, default=str)
            print(f"Findings saved to: {output_file}")
        
        conn.close()
        
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    # Path to the database
    db_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918\state.vscdb"
    backup_path = r"C:\Users\robie\AppData\Roaming\Cursor\User\workspaceStorage\53725de4b99ffb0be1f96c1045b09918\state.vscdb.backup"
    
    print("=" * 60)
    print("Cursor Chat History Extractor")
    print("=" * 60)
    print()
    
    # Try main database first
    if os.path.exists(db_path):
        print("Analyzing main database...")
        extract_chat_history(db_path, "chat_analysis_main.json")
        print()
    
    # Try backup database
    if os.path.exists(backup_path):
        print("Analyzing backup database...")
        extract_chat_history(backup_path, "chat_analysis_backup.json")
        print()
    
    print("=" * 60)
    print("Analysis complete!")
    print("=" * 60)

