import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { ComingSoon } from './components/ComingSoon.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ComingSoon>
      <App />
    </ComingSoon>
  </StrictMode>,
)
