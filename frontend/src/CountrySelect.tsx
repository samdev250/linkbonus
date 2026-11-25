import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent } from 'react';
import { countryCodes, countryName, flagEmoji } from './countries';
import './country-select.css';

type CountrySelectProps = {
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  placeholder?: string;
};

export function CountrySelect({ value, onChange, required = false, placeholder = 'Search for a country' }: CountrySelectProps) {
  const id = useId();
  const root = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const selectedLabel = value ? `${flagEmoji(value)}  ${countryName(value)}` : '';
  const options = useMemo(() => {
    const search = query.trim().toLocaleLowerCase();
    return countryCodes
      .map(code => ({ code, name: countryName(code) }))
      .filter(country => !search || country.name.toLocaleLowerCase().includes(search) || country.code.toLowerCase().includes(search))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [query]);

  useEffect(() => {
    const closeOnOutsideClick = (event: MouseEvent) => {
      if (root.current && !root.current.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', closeOnOutsideClick);
    return () => document.removeEventListener('mousedown', closeOnOutsideClick);
  }, []);

  const choose = (code: string) => {
    onChange(code);
    setQuery('');
    setOpen(false);
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setOpen(true);
      setActiveIndex(index => Math.min(index + 1, options.length - 1));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setActiveIndex(index => Math.max(index - 1, 0));
    } else if (event.key === 'Enter' && open && options[activeIndex]) {
      event.preventDefault();
      choose(options[activeIndex].code);
    } else if (event.key === 'Escape') {
      setOpen(false);
      setQuery('');
    }
  };

  return <div className="country-combobox" ref={root}>
    <input
      id={id}
      role="combobox"
      aria-autocomplete="list"
      aria-expanded={open}
      aria-controls={`${id}-options`}
      aria-activedescendant={open && options[activeIndex] ? `${id}-option-${options[activeIndex].code}` : undefined}
      autoComplete="off"
      required={required && !value}
      value={open ? query : selectedLabel}
      placeholder={placeholder}
      onFocus={() => { setOpen(true); setQuery(''); setActiveIndex(0); }}
      onChange={event => { onChange(''); setQuery(event.target.value); setActiveIndex(0); setOpen(true); }}
      onKeyDown={handleKeyDown}
    />
    {open&&<div className="country-options" id={`${id}-options`} role="listbox" aria-label="Countries and territories">
      {options.map((country, index) => <button
        id={`${id}-option-${country.code}`}
        className={`country-option ${index === activeIndex ? 'active' : ''}`}
        key={country.code}
        type="button"
        role="option"
        aria-selected={country.code === value}
        onMouseEnter={() => setActiveIndex(index)}
        onMouseDown={event => event.preventDefault()}
        onClick={() => choose(country.code)}
      >
        <span>{flagEmoji(country.code)}</span>
        <span>{country.name}</span>
        <small>{country.code}</small>
      </button>)}
      {!options.length&&<div className="country-empty">No matching country found.</div>}
    </div>}
  </div>;
}
