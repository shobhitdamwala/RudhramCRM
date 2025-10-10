import express from "express";
import User from "../Models/userSchema.js";
import jwt from "jsonwebtoken";
import mongoose from "mongoose";

    export const registerUser = async (req, res) => {
    try {
        const {
        fullName,
        email,
        phone,
        city,
        state,
        role,
        subCompany,
        password,
        } = req.body;

        let subCompanyId = null;
        if (subCompany && mongoose.Types.ObjectId.isValid(subCompany)) {
        subCompanyId = subCompany;
        }

        // ✅ Avatar upload (if file present)
        let avatarUrl = null;
        if (req.file) {
        avatarUrl = `/uploads/${req.file.filename}`;
        }

        // Basic validation
        if (!fullName || !email || !role || !password) {
        return res.status(400).json({
            success: false,
            message: "Full name, email, role, and password are required.",
        });
        }

        if (!["SUPER_ADMIN","ADMIN","TEAM_MEMBER","CLIENT"].includes(role)) {
        return res.status(400).json({
            success: false,
            message: "Invalid role specified.",
        });
        }

        // Check for existing user
        const existingUser = await User.findOne({ email });
        if (existingUser) {
        return res.status(409).json({
            success: false,
            message: "Email already in use.",
        });
        }

        // Hash password
        const hashedPassword = await User.hashPassword(password);

        // Create and save user
        const newUser = new User({
        fullName,
        email,
        phone,
        city,
        state,
        role,
        subCompany: subCompanyId,
        passwordHash: hashedPassword,
        avatarUrl, // ✅ save uploaded avatar
        });

        const savedUser = await newUser.save();

        return res.status(201).json({
        success: true,
        message: "User registered successfully.",
        userId: savedUser._id,
        avatar: avatarUrl,
        });
    } catch (err) {
        console.error("Registration error:", err);
        return res.status(500).json({
        success: false,
        message: "Server error during registration.",
        error: err.message,
        });
    }
    };

export const loginUser = async (req, res) => {
  try {
    const { fullName, password } = req.body;

    // 🧩 Validate input
    if (!fullName || !password) {
      return res.status(400).json({
        success: false,
        message: "Full name and password are required.",
      });
    }

    // 🧩 Find user (case-insensitive)
    const user = await User.findOne({
      fullName: { $regex: new RegExp(`^${fullName}$`, "i") },
    }).select("+passwordHash");

    if (!user) {
      return res.status(401).json({
        success: false,
        message: "Invalid name or password.",
      });
    }

    // 🧩 Verify password
    const isMatch = await user.verifyPassword(password);
    if (!isMatch) {
      return res.status(401).json({
        success: false,
        message: "Invalid name or password.",
      });
    }

    // 🧩 Generate JWT Token
    const token = jwt.sign(
      { userId: user._id, role: user.role },
      process.env.JWT_SECRET || "your_jwt_secret",
      { expiresIn: process.env.JWT_EXPIRES_IN || "7d" }
    );

    // 🧩 Update last login
    user.lastLoginAt = new Date();
    await user.save();

    // 🧩 Cookie options
    const cookieOptions = {
      httpOnly: true, // ✅ can't be accessed via JS
      secure: process.env.NODE_ENV === "production", // ✅ HTTPS only in prod
      sameSite: "Strict",
      maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
      path: "/", // cookie available for entire site
    };

    // 🧩 Send cookie + response
    res
      .cookie("auth_token", token, cookieOptions)
      .status(200)
      .json({
        success: true,
        message: "Login successful.",
        token,
        user: {
          id: user._id,
          fullName: user.fullName,
          email: user.email,
          phone: user.phone,
          role: user.role,
          subCompany: user.subCompany,
          avatarUrl: user.avatarUrl,
        },
      });
  } catch (err) {
    console.error("Login Error:", err);
    return res.status(500).json({
      success: false,
      message: "Server error during login.",
      error: err.message,
    });
  }
};

export const getUserProfile = async (req, res) => {
  try {
    // 🧩 Get token from header
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({
        success: false,
        message: "No token provided or invalid format.",
      });
    }

    const token = authHeader.split(" ")[1];

    // 🧩 Verify token
    const decoded = jwt.verify(
      token,
      process.env.JWT_SECRET || "your_jwt_secret"
    );

    // 🧩 Find user by ID
    const user = await User.findById(decoded.userId).select("-passwordHash");

    if (!user) {
      return res.status(404).json({
        success: false,
        message: "User not found.",
      });
    }

    // 🧩 Send user data
    return res.status(200).json({
      success: true,
      user,
    });
  } catch (err) {
    console.error("Get user error:", err);
    return res.status(500).json({
      success: false,
      message: "Server error while fetching user.",
      error: err.message,
    });
  }
};

// ✅ Get all users where role = TEAM_MEMBER
export const getAllTeamMembers = async (req, res) => {
  try {
    // 🧩 Fetch users with role TEAM_MEMBER
    const teamMembers = await User.find({ role: "TEAM_MEMBER" }).select(
      "-passwordHash" // exclude sensitive field
    );

    // 🧩 If no team members found
    if (!teamMembers || teamMembers.length === 0) {
      return res.status(404).json({
        success: false,
        message: "No team members found.",
      });
    }

    // 🧩 Success response
    return res.status(200).json({
      success: true,
      count: teamMembers.length,
      teamMembers,
    });
  } catch (err) {
    console.error("Error fetching team members:", err);
    return res.status(500).json({
      success: false,
      message: "Server error while fetching team members.",
      error: err.message,
    });
  }
};

export const updateTeamMember = async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: "Invalid team member ID.",
      });
    }

    const existingMember = await User.findOne({ _id: id, role: "TEAM_MEMBER" }).select("+passwordHash");
    if (!existingMember) {
      return res.status(404).json({
        success: false,
        message: "Team member not found.",
      });
    }

    const { fullName, email, phone, city, state, subCompany, password, role } = req.body;

    // 🧩 Avatar upload
    let avatarUrl = existingMember.avatarUrl;
    if (req.file) {
      avatarUrl = `/uploads/${req.file.filename}`;
    }

    // 🧩 Update password if provided, else keep old one
    let passwordHash = existingMember.passwordHash;
    if (password && password.trim().length > 0) {
      passwordHash = await User.hashPassword(password);
    }

    // 🧩 Update fields
    existingMember.fullName = fullName || existingMember.fullName;
    existingMember.email = email || existingMember.email;
    existingMember.phone = phone || existingMember.phone;
    existingMember.city = city || existingMember.city;
    existingMember.state = state || existingMember.state;
    existingMember.subCompany = subCompany || existingMember.subCompany;
    existingMember.avatarUrl = avatarUrl;
    existingMember.passwordHash = passwordHash; // 🟢 Always set it
    if (role) existingMember.role = role;

    const updatedMember = await existingMember.save();

    return res.status(200).json({
      success: true,
      message: "Team member updated successfully.",
      teamMember: updatedMember,
    });
  } catch (err) {
    console.error("Update team member error:", err);
    return res.status(500).json({
      success: false,
      message: "Server error while updating team member.",
      error: err.message,
    });
  }
};


// ✅ Delete a team member by ID
export const deleteTeamMember = async (req, res) => {
  try {
    const { id } = req.params;

    // 🧩 Validate ID
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: "Invalid team member ID.",
      });
    }

    // 🧩 Check if user exists and is a TEAM_MEMBER
    const member = await User.findOne({ _id: id, role: "TEAM_MEMBER" });
    if (!member) {
      return res.status(404).json({
        success: false,
        message: "Team member not found.",
      });
    }

    // 🧩 Delete user
    await User.findByIdAndDelete(id);

    return res.status(200).json({
      success: true,
      message: "Team member deleted successfully.",
    });
  } catch (err) {
    console.error("Delete team member error:", err);
    return res.status(500).json({
      success: false,
      message: "Server error while deleting team member.",
      error: err.message,
    });
  }
};
