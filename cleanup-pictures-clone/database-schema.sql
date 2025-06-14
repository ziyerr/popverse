-- Supabase Database Schema for IP Character Generation System (Updated for Auth)
-- Run these commands in your Supabase SQL editor

-- Note: We use Supabase's built-in auth.users table instead of custom users table
-- The auth.users table is automatically created and managed by Supabase Auth

-- Generation tasks table (updated to reference auth.users)
CREATE TABLE IF NOT EXISTS generation_tasks (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    task_type TEXT NOT NULL,
    prompt TEXT NOT NULL,
    original_image_url TEXT,
    result_image_url TEXT,
    result_data JSONB,
    error_message TEXT,
    batch_id TEXT,
    parent_character_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User IP characters table (updated to reference auth.users)
CREATE TABLE IF NOT EXISTS user_ip_characters (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    main_image_url TEXT NOT NULL,
    left_view_url TEXT,
    back_view_url TEXT,
    model_3d_url TEXT,
    merchandise_urls JSONB,
    merchandise_task_status TEXT CHECK (merchandise_task_status IN ('pending', 'processing', 'completed', 'failed')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_generation_tasks_user_id ON generation_tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_generation_tasks_status ON generation_tasks(status);
CREATE INDEX IF NOT EXISTS idx_generation_tasks_task_type ON generation_tasks(task_type);
CREATE INDEX IF NOT EXISTS idx_generation_tasks_created_at ON generation_tasks(created_at);
CREATE INDEX IF NOT EXISTS idx_generation_tasks_batch_id ON generation_tasks(batch_id);
CREATE INDEX IF NOT EXISTS idx_user_ip_characters_user_id ON user_ip_characters(user_id);
CREATE INDEX IF NOT EXISTS idx_user_ip_characters_created_at ON user_ip_characters(created_at);

-- Enable Row Level Security (RLS)
ALTER TABLE generation_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_ip_characters ENABLE ROW LEVEL SECURITY;

-- Drop old policies if they exist
DROP POLICY IF EXISTS "Users can view own tasks" ON generation_tasks;
DROP POLICY IF EXISTS "Users can insert own tasks" ON generation_tasks;
DROP POLICY IF EXISTS "Users can update own tasks" ON generation_tasks;
DROP POLICY IF EXISTS "Users can view own characters" ON user_ip_characters;
DROP POLICY IF EXISTS "Users can insert own characters" ON user_ip_characters;
DROP POLICY IF EXISTS "Users can update own characters" ON user_ip_characters;

-- Create RLS policies for generation_tasks (using auth.uid())
CREATE POLICY "Users can view own tasks" ON generation_tasks 
FOR SELECT USING (user_id = auth.uid() OR user_id IS NULL);

CREATE POLICY "Users can insert own tasks" ON generation_tasks 
FOR INSERT WITH CHECK (user_id = auth.uid() OR user_id IS NULL);

CREATE POLICY "Users can update own tasks" ON generation_tasks 
FOR UPDATE USING (user_id = auth.uid() OR user_id IS NULL);

CREATE POLICY "Service role can manage all tasks" ON generation_tasks 
FOR ALL USING (auth.role() = 'service_role');

-- Create RLS policies for user_ip_characters (using auth.uid())
CREATE POLICY "Users can view own characters" ON user_ip_characters 
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can insert own characters" ON user_ip_characters 
FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own characters" ON user_ip_characters 
FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete own characters" ON user_ip_characters 
FOR DELETE USING (user_id = auth.uid());

-- Create storage bucket for generated images (if not exists)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('generated-images', 'generated-images', true)
ON CONFLICT (id) DO NOTHING;

-- Create storage policies for generated images
CREATE POLICY "Public can view generated images" ON storage.objects 
FOR SELECT USING (bucket_id = 'generated-images');

CREATE POLICY "Authenticated users can upload images" ON storage.objects 
FOR INSERT WITH CHECK (bucket_id = 'generated-images' AND auth.role() = 'authenticated');

CREATE POLICY "Users can update their own images" ON storage.objects 
FOR UPDATE USING (bucket_id = 'generated-images' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can delete their own images" ON storage.objects 
FOR DELETE USING (bucket_id = 'generated-images' AND auth.uid()::text = (storage.foldername(name))[1]);

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger to automatically update updated_at for generation_tasks
DROP TRIGGER IF EXISTS update_generation_tasks_updated_at ON generation_tasks;
CREATE TRIGGER update_generation_tasks_updated_at
    BEFORE UPDATE ON generation_tasks
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Migration Notes:
-- 1. If you have existing data in old 'users' table, you'll need to migrate it manually
-- 2. Update any application code to use auth.uid() instead of custom user IDs
-- 3. Test all RLS policies with your application after applying this schema
-- 4. The auth.users table is managed by Supabase Auth automatically

-- Drop old tables if they exist (CAREFUL: This will delete data!)
-- Uncomment these lines only if you're sure you want to remove old data:
-- DROP TABLE IF EXISTS users CASCADE;

-- Optional: Create a view to easily access user metadata from auth.users
CREATE OR REPLACE VIEW user_profiles AS
SELECT 
    id,
    email,
    (raw_user_meta_data->>'username')::text as username,
    created_at,
    updated_at,
    last_sign_in_at
FROM auth.users;

-- Grant access to the view for authenticated users
GRANT SELECT ON user_profiles TO authenticated;

-- Create RLS policy for the view
ALTER VIEW user_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own profile" ON user_profiles 
FOR SELECT USING (id = auth.uid());