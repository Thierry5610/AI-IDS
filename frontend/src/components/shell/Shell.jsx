/**
 * Shell — wraps every page.
 * Props:
 *   title (string) — forwarded to Topbar
 *   children       — page content, rendered inside .bento
 */
import Rail   from './Rail'
import Topbar from './Topbar'

export default function Shell({ title, children }) {
  return (
    <div className="app">
      <Rail />
      <div className="main">
        <Topbar title={title} />
        <div className="content">
          <div className="bento">
            {children}
          </div>
        </div>
      </div>
    </div>
  )
}
