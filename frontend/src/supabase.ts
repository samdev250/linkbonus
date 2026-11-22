import { createClient } from '@supabase/supabase-js';
import {PROJECT_SUPABASE_PUBLISHABLE_KEY,PROJECT_SUPABASE_URL} from './supabaseConfig';

const url = import.meta.env.VITE_SUPABASE_URL || PROJECT_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY || PROJECT_SUPABASE_PUBLISHABLE_KEY;

export const supabase = url && anonKey
  ? createClient(url, anonKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } })
  : null;

export const apiUrl = import.meta.env.VITE_API_URL || (import.meta.env.DEV ? 'http://localhost:4000/api' : '/api');
export const siteUrl = String(import.meta.env.VITE_SITE_URL || window.location.origin).replace(/\/$/, '');

export const referralUrl = (code: string) => `${siteUrl}/?ref=${encodeURIComponent(code)}`;

export const rememberReferral = () => {
  const params = new URLSearchParams(window.location.search);
  const ref = params.get('ref');
  const invite = params.get('invite');
  if (ref) sessionStorage.setItem('lb_ref', ref.trim());
  if (invite) sessionStorage.setItem('lb_invite', invite.trim());
};

export const getStoredRef = () => sessionStorage.getItem('lb_ref') || '';
export const getStoredInvite = () => sessionStorage.getItem('lb_invite') || '';
export const clearReferral = () => {
  sessionStorage.removeItem('lb_ref');
  sessionStorage.removeItem('lb_invite');
};
