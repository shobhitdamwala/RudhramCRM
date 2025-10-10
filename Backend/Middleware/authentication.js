import jwt from "jsonwebtoken";

export const authenticate = (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        return res.status(401).json({ message: "Unauthorized: No token provided" });
    }
    const token = authHeader.split(" ")[1]; 
    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET || "your_jwt_secret");
        req.user = decoded; // userId, role available now
        next();
    } catch (err) {
        return res.status(403).json({ message: "Invalid or expired token" });
    }
};

export const authorize = (roles = []) => {
    if (typeof roles === 'string') {
        roles = [roles];
    }
    return (req, res, next) => {
        if (!roles.includes(req.user.role)) {
            return res.status(403).json({ message: "Forbidden: You do not have access to this resource" });
        }
        next();
    };
};