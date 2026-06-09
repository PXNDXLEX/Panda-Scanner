-- Ejecuta esto en el SQL Editor de tu panel de Supabase para arreglar el error 500
-- "infinite recursion detected in policy for relation networks"

-- 1. Creamos una función que corre con permisos de administrador (SECURITY DEFINER)
-- Esto permite revisar quién es el dueño de la red sin disparar las reglas de seguridad infinitamente.
CREATE OR REPLACE FUNCTION public.is_network_owner(net_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS(SELECT 1 FROM public.networks WHERE id = net_id AND owner_id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Borramos la política problemática que causaba el ciclo infinito
DROP POLICY IF EXISTS "Owners can manage shares" ON public.network_shares;

-- 3. Creamos la política corregida usando la función segura
CREATE POLICY "Owners can manage shares" ON public.network_shares FOR ALL USING (
  public.is_network_owner(network_id)
);

-- 4. Asegurar que la columna gateway_mac exista (necesaria para la nueva versión)
ALTER TABLE public.networks ADD COLUMN IF NOT EXISTS gateway_mac TEXT;

-- 5. Dar permisos para que las políticas puedan leer el email del usuario
GRANT SELECT ON auth.users TO authenticated;

-- 6. Añadir restricción de unicidad para dispositivos (necesario para el upsert)
ALTER TABLE public.devices ADD CONSTRAINT unique_network_ip UNIQUE (network_id, ip_address);
