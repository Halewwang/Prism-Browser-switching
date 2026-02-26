import { clsx } from 'clsx';
import { type ButtonHTMLAttributes, type ReactNode } from 'react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  variant?: 'primary' | 'outline' | 'ghost';
  className?: string;
}

export function Button({ children, variant = 'primary', className, ...props }: ButtonProps) {
  const baseStyles = "px-8 py-4 transition-all duration-500 ease-out font-sans font-medium text-[10px] tracking-[0.25em] uppercase cursor-pointer";
  
  const variants = {
    primary: "bg-charcoal text-white hover:bg-bronze border border-charcoal hover:border-bronze",
    outline: "border border-charcoal text-charcoal hover:bg-charcoal hover:text-white",
    ghost: "text-charcoal hover:text-bronze p-0 border-none relative after:content-[''] after:absolute after:left-0 after:bottom-0 after:h-[1px] after:bg-bronze after:w-0 hover:after:w-full after:transition-all after:duration-500"
  } as const;

  const finalVariant = variants[variant];

  return (
    <button className={clsx(baseStyles, finalVariant, className)} {...props}>
      {children}
    </button>
  );
}
