import { createClient } from '@supabase/supabase-js';
import {PROJECT_SUPABASE_PUBLISHABLE_KEY,PROJECT_SUPABASE_URL} from './supabaseConfig';

const url = import.meta.env.VITE_SUPABASE_URL || PROJECT_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY || PROJECT_SUPABASE_PUBLISHABLE_KEY;

export const supabase = url && anonKey
  ? createClient(url, anonKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } })
  : null;

export const apiUrl = import.meta.env.VITE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000/api' : '/api');
