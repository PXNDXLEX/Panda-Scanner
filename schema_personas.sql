-- Create persons table
CREATE TABLE IF NOT EXISTS public.persons (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.persons ENABLE ROW LEVEL SECURITY;

-- Owner policies for persons
CREATE POLICY "Users can manage their own persons" ON public.persons FOR ALL USING (
  auth.uid() = user_id
);

-- Update devices table
ALTER TABLE public.devices ADD COLUMN IF NOT EXISTS person_id UUID REFERENCES public.persons(id) ON DELETE SET NULL;

-- Since devices has a new column, we don't necessarily need to change its RLS because devices RLS is based on network_id.
-- Persons are isolated to the user, and devices are linked to persons.

-- Realtime
alter publication supabase_realtime add table persons;
