# Supabase Setup Prompt for Messaging Image Support

Copy and paste this prompt into your Supabase AI assistant or use it as a guide for manual setup:

---

## Prompt for Supabase AI Assistant:

**"I need to add image/picture support to my messaging system. Please set up the following:**

### 1. Create Storage Bucket for Message Images

Create a new storage bucket called `message-images` with the following configuration:
- **Bucket ID**: `message-images`
- **Public**: `false` (private bucket - users must be authenticated)
- **File size limit**: 10MB per file
- **Allowed MIME types**: `image/jpeg`, `image/png`, `image/gif`, `image/webp`

### 2. Storage Bucket RLS Policies

Create Row Level Security policies for the `message-images` bucket:

**Policy 1: Users can upload images to messages they create**
```sql
CREATE POLICY "Users can upload message images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'message-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);
```

**Policy 2: Users can view images from messages they created or received**
```sql
CREATE POLICY "Users can view message images"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'message-images' AND
  (
    (storage.foldername(name))[1] = auth.uid()::text OR
    EXISTS (
      SELECT 1 FROM public.text_messages tm
      JOIN public.text_message_log tml ON tm.id = tml.text_message_id
      WHERE tml.recipient_id = auth.uid()
      AND tm.image_urls::text[] @> ARRAY[storage.objects.name]
    )
  )
);
```

**Policy 3: Users can delete images from messages they created**
```sql
CREATE POLICY "Users can delete their own message images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'message-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);
```

### 3. Update `text_messages` Table Schema

Add the following columns to the `public.text_messages` table:

```sql
-- Add column to store array of image URLs
ALTER TABLE public.text_messages
ADD COLUMN IF NOT EXISTS image_urls text[] DEFAULT ARRAY[]::text[];

-- Add index for faster queries on messages with images
CREATE INDEX IF NOT EXISTS idx_text_messages_has_images 
ON public.text_messages USING gin(image_urls)
WHERE array_length(image_urls, 1) > 0;

-- Add comment for documentation
COMMENT ON COLUMN public.text_messages.image_urls IS 
'Array of Supabase Storage URLs for images attached to this message. Images are stored in the message-images bucket.';
```

### 4. Update `text_message_template` Table Schema

Add support for images in templates:

```sql
-- Add column to store array of image URLs for templates
ALTER TABLE public.text_message_template
ADD COLUMN IF NOT EXISTS image_urls text[] DEFAULT ARRAY[]::text[];

-- Add comment for documentation
COMMENT ON COLUMN public.text_message_template.image_urls IS 
'Array of Supabase Storage URLs for images in this template. Images are stored in the message-images bucket.';
```

### 5. Create Helper Function for Image Cleanup (Optional but Recommended)

Create a function to clean up orphaned images when messages are deleted:

```sql
-- Function to delete images from storage when message is soft-deleted
CREATE OR REPLACE FUNCTION cleanup_message_images()
RETURNS TRIGGER AS $$
DECLARE
  image_url text;
BEGIN
  -- Only process if message is being soft-deleted (deleted_at is being set)
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    -- Delete each image from storage
    FOREACH image_url IN ARRAY OLD.image_urls
    LOOP
      -- Extract file path from URL
      -- Format: https://[project].supabase.co/storage/v1/object/public/message-images/[user_id]/[filename]
      -- We need to extract: [user_id]/[filename]
      BEGIN
        PERFORM storage.objects.delete('message-images', 
          substring(image_url from 'message-images/(.*)$'));
      EXCEPTION WHEN OTHERS THEN
        -- Log error but don't fail the transaction
        RAISE WARNING 'Failed to delete image %: %', image_url, SQLERRM;
      END;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to call cleanup function
DROP TRIGGER IF EXISTS trg_cleanup_message_images ON public.text_messages;
CREATE TRIGGER trg_cleanup_message_images
  BEFORE UPDATE ON public.text_messages
  FOR EACH ROW
  WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
  EXECUTE FUNCTION cleanup_message_images();
```

### 6. Update RLS Policies for `text_messages` (if needed)

Ensure your existing RLS policies on `text_messages` allow users to update the `image_urls` column when creating/editing their own messages.

### 7. Storage Folder Structure

The storage bucket should organize images by user ID:
- Path format: `{user_id}/{message_id}_{timestamp}_{index}.{ext}`
- Example: `550e8400-e29b-41d4-a716-446655440000/msg_123_20250123_001.jpg`

This structure:
- Makes it easy to identify who uploaded the image
- Prevents filename conflicts
- Allows efficient cleanup per user

### Summary

After setup, I should have:
1. ✅ A `message-images` storage bucket with proper RLS policies
2. ✅ `image_urls` column added to `text_messages` table
3. ✅ `image_urls` column added to `text_message_template` table
4. ✅ Index for efficient queries on messages with images
5. ✅ Optional cleanup function to delete images when messages are deleted
6. ✅ Proper security policies ensuring users can only access their own images or images from messages they received

Please confirm when all items are set up, and let me know if any adjustments are needed based on your existing RLS policies."

---

## Manual Setup Instructions (Alternative)

If you prefer to set up manually in Supabase Dashboard:

### Step 1: Create Storage Bucket
1. Go to **Storage** in Supabase Dashboard
2. Click **New bucket**
3. Name: `message-images`
4. **Public bucket**: OFF (unchecked)
5. **File size limit**: 10MB
6. **Allowed MIME types**: `image/jpeg,image/png,image/gif,image/webp`
7. Click **Create bucket**

### Step 2: Add Table Columns
1. Go to **Table Editor** → `text_messages`
2. Click **Add column**
3. Name: `image_urls`
4. Type: `text[]` (array of text)
5. Default value: `{}` (empty array)
6. Click **Save**

7. Go to **Table Editor** → `text_message_template`
8. Click **Add column**
9. Name: `image_urls`
10. Type: `text[]` (array of text)
11. Default value: `{}` (empty array)
12. Click **Save**

### Step 3: Create Storage Policies
1. Go to **Storage** → `message-images` → **Policies**
2. Create the three policies listed above using the SQL Editor

### Step 4: Create Index (Optional but Recommended)
1. Go to **SQL Editor**
2. Run the index creation SQL from section 3 above

---

## Testing Checklist

After setup, verify:
- [ ] Storage bucket `message-images` exists and is private
- [ ] `text_messages.image_urls` column exists and accepts text arrays
- [ ] `text_message_template.image_urls` column exists and accepts text arrays
- [ ] Storage policies allow authenticated users to upload/view/delete
- [ ] You can upload a test image to the bucket manually
- [ ] RLS policies prevent unauthorized access

---

## Notes

- **File Size**: 10MB limit per image (adjustable in bucket settings)
- **Image Formats**: JPEG, PNG, GIF, WebP supported
- **Storage Path**: Images organized by user ID for easy management
- **Cleanup**: Optional trigger automatically deletes images when messages are soft-deleted
- **Security**: All images are private - only accessible to message creator and recipients
