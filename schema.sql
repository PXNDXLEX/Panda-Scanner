-- Supabase Schema for Panda Scanner

-- 1. Profiles Table (Extends auth.users)
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  first_name TEXT,
  last_name TEXT,
  country TEXT,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Trigger to create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, first_name, last_name, country)
  VALUES (
    new.id,
    new.email,
    new.raw_user_meta_data->>'first_name',
    new.raw_user_meta_data->>'last_name',
    new.raw_user_meta_data->>'country'
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 2. Networks Table
CREATE TABLE public.networks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  gateway_mac TEXT,
  gateway_ip TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Network Shares Table (For sharing networks)
CREATE TABLE public.network_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network_id UUID REFERENCES public.networks(id) ON DELETE CASCADE NOT NULL,
  guest_email TEXT NOT NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(network_id, guest_email)
);

-- 4. Devices Table
CREATE TABLE public.devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network_id UUID REFERENCES public.networks(id) ON DELETE CASCADE NOT NULL,
  ip_address TEXT,
  mac_address TEXT,
  hostname TEXT,
  brand TEXT,
  custom_name TEXT,
  icon_type TEXT DEFAULT 'device_unknown',
  is_favorite BOOLEAN DEFAULT false,
  last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Device History Table (For tracking connections/disconnections)
CREATE TABLE public.device_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id UUID REFERENCES public.devices(id) ON DELETE CASCADE NOT NULL,
  status TEXT CHECK (status IN ('online', 'offline')),
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Setup Row Level Security (RLS)

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.networks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.network_shares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_history ENABLE ROW LEVEL SECURITY;

-- Profiles: Users can read their own, and others if they share a network.
-- For simplicity, let's allow users to read/update their own profile.
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Networks: Owner or Guest with accepted share
CREATE POLICY "Users can view owned or shared networks" ON public.networks FOR SELECT USING (
  auth.uid() = owner_id OR 
  EXISTS (
    SELECT 1 FROM public.network_shares 
    WHERE network_shares.network_id = networks.id 
    AND network_shares.guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
    AND network_shares.status = 'accepted'
  )
);
CREATE POLICY "Users can insert networks" ON public.networks FOR INSERT WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "Users can update owned or shared networks" ON public.networks FOR UPDATE USING (
  auth.uid() = owner_id OR 
  EXISTS (
    SELECT 1 FROM public.network_shares 
    WHERE network_shares.network_id = networks.id 
    AND network_shares.guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
    AND network_shares.status = 'accepted'
  )
);
CREATE POLICY "Users can delete owned networks" ON public.networks FOR DELETE USING (auth.uid() = owner_id);

-- Devices: Users can view/modify devices if they have access to the network
CREATE POLICY "Users can access devices for accessible networks" ON public.devices FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.networks 
    WHERE networks.id = devices.network_id 
    AND (
      networks.owner_id = auth.uid() OR 
      EXISTS (
        SELECT 1 FROM public.network_shares 
        WHERE network_shares.network_id = networks.id 
        AND network_shares.guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
        AND network_shares.status = 'accepted'
      )
    )
  )
);

-- Device History: Same as Devices
CREATE POLICY "Users can access history for accessible networks" ON public.device_history FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.devices 
    JOIN public.networks ON networks.id = devices.network_id
    WHERE devices.id = device_history.device_id
    AND (
      networks.owner_id = auth.uid() OR 
      EXISTS (
        SELECT 1 FROM public.network_shares 
        WHERE network_shares.network_id = networks.id 
        AND network_shares.guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
        AND network_shares.status = 'accepted'
      )
    )
  )
);

-- Network Shares: 
-- 1. Network owner can see, insert, delete shares for their networks.
-- 2. User with the guest_email can see and update (accept/reject) the share.
CREATE POLICY "Owners can manage shares" ON public.network_shares FOR ALL USING (
  EXISTS (SELECT 1 FROM public.networks WHERE id = network_id AND owner_id = auth.uid())
);
CREATE POLICY "Guests can view their invites" ON public.network_shares FOR SELECT USING (
  guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
);
CREATE POLICY "Guests can accept/reject invites" ON public.network_shares FOR UPDATE USING (
  guest_email = (SELECT email FROM auth.users WHERE id = auth.uid())
);
